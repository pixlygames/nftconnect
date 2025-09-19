// script.js - Adapted from original ton_connect/index.js and index.html

// Global variable for TonConnectUI instance
let tonConnectUI = null;
// Global variable to store wallet info
let currentWalletInfo = null;
// Global variable to store the server-generated payload/nonce
let serverNoncePayload = null;
// Flag to ensure initialization only happens once
let isInitialized = false;

// --- NUI Loading and Initialization ---

$(function () {
    // Initially hide the UI
    $(".OurDiv").hide();

    // Listen for messages from the client script
    window.addEventListener('message', function(event) {
        var item = event.data;
        if (item !== undefined && item.type === "ui") {
            if (item.display === true) {
                $(".OurDiv").fadeIn(300); // Show UI
                // Initialize only once when UI is first shown
                if (!isInitialized) {
                    initializeTonConnect();
                    isInitialized = true;
                } else if (tonConnectUI) {
                    // If already initialized and reopening, reset state and get new payload
                    console.log("Re-opening NUI. Resetting state and requesting new payload.");
                    resetState();
                    getInitialPayload(); // Request payload again
                }
            } else {
                $(".OurDiv").fadeOut(300); // Hide UI
                // Disconnect wallet and clear state when UI is hidden
                if (tonConnectUI && tonConnectUI.connected) {
                    console.log("Disconnecting wallet on UI close.");
                    tonConnectUI.disconnect().catch(e => console.warn("Error disconnecting on close:", e));
                }
                // Reset global state variables
                resetState();
            }
        } else if (item !== undefined && item.action === 'nftData') {
            // Display received NFT data
            console.log("Received NFT data:", item.data);
            displayNftData(item.data);
        } else if (item !== undefined && item.action === 'verificationFailed') {
            console.error("Verification failed:", item.message);
            $('#nft-display').html(`<p style="color: #ff4d4d;">Verification Failed: ${item.message || 'Unknown error'}</p>`);
        }
    });

    // Handle ESC key press to close NUI and disable focus
    document.addEventListener('keydown', function(event) {
        if (event.key === 'Escape') {
            // Request Lua script to hide UI, which will trigger the display(false) logic via message
            $.post(`https://${GetParentResourceName()}/hideUI`, JSON.stringify({}));
        }
    });
});

// Reset global state and UI elements
function resetState() {
    currentWalletInfo = null;
    serverNoncePayload = null;
    $('#nft-display').html(''); // Clear display area
}

// Function to initialize TonConnectUI and request initial payload
async function initializeTonConnect() {
    // Removed check for existing tonConnectUI as it's handled by isInitialized flag

    try {
        // 1. Get Manifest URL from client.lua
        const manifestUrl = await new Promise((resolve, reject) => {
            $.post(`https://${GetParentResourceName()}/getManifestUrl`, JSON.stringify({}), (url) => {
              if (url) {
                 console.log("Manifest URL received via post: ", url);
                 resolve(url);
              } else {
                 console.error("Manifest URL response was empty or null.");
                 reject("Manifest URL not provided by client script.");
              }
            }).fail((jqXHR, textStatus, errorThrown) => {
                 console.error("Failed to request manifest URL from client script:", textStatus, errorThrown);
                 reject("Could not fetch Manifest URL.");
            });
        });

        if (!manifestUrl) {
            throw new Error("Manifest URL is missing.");
        }

        // 2. Initialize TonConnectUI
        const tonConnectUiOptions = {
            manifestUrl: manifestUrl,
            buttonRootId: 'connect-button-root'
        };

        console.log("Initializing TonConnectUI with options:", tonConnectUiOptions);
        tonConnectUI = new TON_CONNECT_UI.TonConnectUI(tonConnectUiOptions);

        // 3. Request Initial Payload (Nonce) from client.lua
        await getInitialPayload(); // This function now sets serverNoncePayload and configures tonConnectUI

        // 4. Subscribe to connection status changes
        tonConnectUI.onStatusChange(async (walletInfo) => {
            currentWalletInfo = walletInfo; // Store latest wallet info

            if (walletInfo) {
                console.log('Wallet status changed:', walletInfo);
                // Check if the connection attempt included a valid TON Proof
                if (walletInfo.connectItems?.tonProof && !('error' in walletInfo.connectItems.tonProof)) {
                    console.log('TON Proof received from wallet connection.');
                    const proof = walletInfo.connectItems.tonProof;

                    // --- BEGIN DEBUG LOGGING ---
                    console.log('[DEBUG] walletInfo object:', JSON.stringify(walletInfo));
                    console.log('[DEBUG] proof object (walletInfo.connectItems.tonProof):', JSON.stringify(proof));
                    if (proof) {
                        console.log('[DEBUG] proof.payload value:', proof.payload);
                        console.log('[DEBUG] typeof proof.payload:', typeof proof.payload);
                    } else {
                        console.log('[DEBUG] proof object is missing or falsy!');
                    }
                    // --- END DEBUG LOGGING ---

                    submitProofForVerification(walletInfo, proof);
                } else if (walletInfo.connectItems?.tonProof && 'error' in walletInfo.connectItems.tonProof) {
                    console.warn('TON Proof attempt failed in wallet:', walletInfo.connectItems.tonProof.error);
                    $('#nft-display').html('<p style="color: #ffcc00;">Wallet connection error or proof rejected.</p>');
                    resetState(); // Clear potentially stale state
                    await getInitialPayload(); // Get a new payload for a retry
                } else if (tonConnectUI.connected) {
                    console.log('Wallet connected, but no new proof in this status change.');
                }

            } else {
                console.log('Wallet disconnected.');
                resetState(); // Clear wallet info, payload, UI
                // Don't get payload immediately on disconnect, wait for next connect attempt
                // await getInitialPayload();
            }
        });

        console.log("TonConnectUI initialized and configured successfully.");

    } catch (error) {
        console.error("Error during TonConnectUI initialization or setup:", error);
        $('#nft-display').html(`<p style="color: #ff4d4d;">Initialization Error: ${error.message || 'Could not set up wallet connection.'}</p>`);
        // Prevent further interaction if init fails badly
        tonConnectUI = null;
        isInitialized = false; // Allow re-initialization attempt
    }
}

// Function to request payload from client script and configure TonConnectUI
async function getInitialPayload() {
    console.log("Requesting initial payload (nonce) from client script...");
    try {
        const response = await $.post(`https://${GetParentResourceName()}/requestPayload`, JSON.stringify({}));
        if (response && response.payload) {
            console.log("Received initial payload:", response.payload);
            serverNoncePayload = response.payload; // Store the nonce

            // Configure TonConnectUI to request proof using this payload
            if (tonConnectUI) {
                tonConnectUI.setConnectRequestParameters({
                    state: 'ready',
                    value: {
                        tonProof: serverNoncePayload
                    }
                });
                console.log("TonConnectUI connect parameters set with server payload.");
            } else {
                 console.error("Cannot set connect parameters: TonConnectUI not initialized.");
            }

        } else {
            console.error("Failed to get payload or invalid response:", response);
            serverNoncePayload = null;
            $('#nft-display').html('<p style="color: #ff4d4d;">Error: Could not retrieve session data.</p>');
            throw new Error("Invalid payload response.");
        }
    } catch (error) {
         console.error("Failed getInitialPayload POST request to Lua:", error);
         serverNoncePayload = null;
         $('#nft-display').html('<p style="color: #ff4d4d;">Error: Failed to fetch session data.</p>');
         throw error;
    }
}


// Function to send the proof and wallet info back to Lua for verification
function submitProofForVerification(walletInfo, proof) {
     if (!walletInfo || !proof || !proof.proof || !proof.proof.payload) {
          console.error("submitProofForVerification FAILED: Missing essential walletInfo or proof.proof data (incl. payload).");
          if(proof && !proof.proof) console.error("[DEBUG] Proof object lacks nested .proof property.");
          else if(proof && proof.proof && !proof.proof.payload) console.error("[DEBUG] Proof object lacks nested .proof.payload property.");

          $('#nft-display').html('<p style="color: #ff4d4d;">Error: Incomplete data received from wallet.</p>');
          return;
     }
     console.log("Submitting proof and wallet info back to Lua...");
     const dataToSend = {
          walletInfo: walletInfo,
          proof: proof
     };
     console.log("[DEBUG] Data being sent to /submitProof:", JSON.stringify(dataToSend));

     $.post(`https://${GetParentResourceName()}/submitProof`, JSON.stringify(dataToSend), function(response) {
          console.log("Response from Lua after submitting proof:", response);
          if (response && response.status === 'received') {
              $('#nft-display').html('<p>Verifying wallet...</p>');
          } else {
               console.warn("Unexpected acknowledgement response from /submitProof:", response);
               $('#nft-display').html('<p style="color: #ffcc00;">Verification submission acknowledged with warnings.</p>');
          }
     }).fail(function(jqXHR, textStatus, errorThrown) {
          console.error("Failed submitProof POST request to Lua.");
          console.error(`[DEBUG] Status: ${textStatus}, Error: ${errorThrown}`);
          if (jqXHR.responseText) {
               console.error("[DEBUG] Response Text from Lua (if any):", jqXHR.responseText);
          }
          $('#nft-display').html('<p style="color: #ff4d4d;">Error: Could not submit proof for verification.</p>');
     });
}

// Function to display NFT data received from client.lua
function displayNftData(nftData) {
    const nftDisplay = $('#nft-display');
    nftDisplay.html(''); // Clear previous data

    if (nftData && nftData.verified === true) {
        if (nftData.nfts && nftData.nfts.length > 0) {
            nftDisplay.append('<p><strong>Wallet Verified!</strong> Your NFTs:</p><ul>');
            nftData.nfts.forEach(nft => {
                const name = nft.metadata?.name || 'Unnamed NFT';
                nftDisplay.append(`<li>${name} (${nft.address.substring(0, 6)}...)</li>`);
                 if(nft.metadata?.image) {
                     nftDisplay.append(`<img src="${nft.metadata.image}" alt="${name}" style="max-width: 100px; max-height: 100px; margin-left: 10px; vertical-align: middle;">`);
                 }
            });
            nftDisplay.append('</ul>');
            if (nftData.rewards && nftData.rewards.length > 0) {
                 nftDisplay.append('<p style="color: #4CAF50;">Rewards are being processed!</p>');
            } else {
                nftDisplay.append('<p style="color: #FFA500;">No specific rewards found for these NFTs based on server config.</p>');
            }
        } else {
            nftDisplay.html('<p><strong>Wallet Verified!</strong> No relevant NFTs found in your wallet based on server configuration.</p>');
        }
    } else if (nftData && nftData.verified === false) {
        nftDisplay.html(`<p style="color: #ff4d4d;">Verification Failed: ${nftData.reason || 'Unknown reason'}</p>`);
    } else {
         nftDisplay.html('<p>Verification submitted. Waiting for results...</p>');
    }
}


// Utility function to get the parent resource name (reverted to regex method)
function GetParentResourceName() {
    const match = window.location.href.match(/fxasset-([^/]+)/) || window.location.href.match(/cfx-nui-([^/]+)/); // Adjusted regex for different environments
    const resourceName = match ? match[1] : 'NFTconnect'; // Default fallback
    // console.log("GetParentResourceName (regex) called, returning:", resourceName);
    return resourceName;
}