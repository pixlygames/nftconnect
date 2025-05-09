# NFTconnect for FiveM (QBcore Framework)

[NFTconnect](https://pixly.games/nftconnect) enables FiveM server owners to easily integrate an in-game marketplace for NFT-based assets like houses and cars. Players connect their crypto wallets, and the NFTs they own automatically appear in-game, granting access to unique assets.

**Server owners earn 40% of every NFT sale made through the marketplace on their server.
Players can easily store cars/houses on their phones, sell them to other players, and transfer them between different servers.**

Watch the [DEMO](https://www.youtube.com/watch?v=qtUUVqL1xOs).

[Cars](https://getgems.io/collection/EQBmuQ8GKlpRja2lN6eXqhT1snEaqkmVOxh-lJ3elOFhxukl) (will add more)

[Houses](https://getgems.io/collection/EQD1tMV65CxBUxqGPcjlOB3Aqs9GNOhNdfm1jqDa-2nCpU18) (will add more)

You can test [here](https://cfx.re/join/va57j5). Just press F12, connect your TON/Telegram wallet, and you'll receive a free hotel room and a car to start the game.

## Overview

This solution consists of several components:

*   **NFTconnect Script**: Handles NFT validation and communication.
*   **Modified ps-housing**: An enhanced version of the popular housing script to support NFT properties.
*   **Modified ps-realtor**: Works with the modified `ps-housing` for property management.
*   **Assets**: Includes MLOs, Shells, car models, and the store UI (`[MLOs]`, `[shells]`, `cars`, `store` folders).
*   **Files to add data for cars and houses**: Includes config.lua, properties_import.sql, properties.sql, vehicles.lua.

**Download all required files [here](https://drive.google.com/drive/folders/1aIIiMnsWhIjrdhCZY1IKlKUtcU6fYy2f?usp=sharing) (GitHub has file limits):**

## Configuration (Mandatory)

**IMPORTANT:** Before starting, you **MUST** configure the `NFTconnect` script with your public TON/Telegram wallet address. Creating wallet takes about 30 seconds we recommend [MyTonWallet](https://mytonwallet.io/). 

1.  Open the `config.lua` file within the `NFTconnect` resource folder.
2.  Find `Config.ServerBuyerWallet` and enter your public TON/Telegram wallet address.

**Failure to set your wallet address will prevent the script from working, and you will not receive commission payouts.**

## Installation

Choose the installation path that matches your server setup:

### Option 1: NFT Cars Only (No Houses)

If you only want to add NFT cars and are already using the standard QBcore framework for vehicles:

1.  Place the `NFTconnect`, `store`, and `cars` folders into your server's `resources` directory.
2.  Ensure `NFTconnect`, `store`, and `cars` are started in your `server.cfg` *after* `qb-core` and other essential resources.
3.  Add the NFT car model names to your `resources/[qb]/qb-core/shared/vehicles.lua` file. You can copy all the vehicle entries directly from the `vehicles.lua` file provided in the download package.

That's it! NFT cars should now be set up.

### Option 2: NFT Cars & Houses (Existing ps-housing User)

If you want both NFT cars and houses, and you already have `ps-housing` installed it's also very easy:

1.  Place the `[MLOs]`, `[shells]`, `NFTconnect`, `cars` and `store` folders into your server's `resources` directory.
2.  **Remove** your existing `ps-housing` and `ps-realtor` resource folders.
3.  Place the **modified** `ps-housing` and `ps-realtor` folders (provided in the download package) into your `resources` directory.
4.  Ensure `NFTconnect`, `store`, `[MLOs]`, `[shells]`, `cars`, and the **modified** `ps-housing` and `ps-realtor` are started in your `server.cfg`. Remember to respect the original `ps-housing` dependencies and start order (e.g., `ox_lib`, `ps-realtor`, `ps-housing`).
5.  Run the provided `properties_import.sql` script against your database.
    *   Open HeidiSQL and connect to your database.
    *   Click "File" -> "Load SQL file...".
    *   Select the `properties_import.sql` file from the download package.
    *   Click the "Execute SQL" button (looks like a blue play icon, or press F9).
    *   This script adds property data (locations, doors, images, descriptions, etc.) to your existing `properties` table. It starts adding properties from `property_id` 1001 onwards, so it should not affect existing properties unless you already have over 1000 properties defined.
6.  Open the `config.lua` file located in your `resources/[qb]/qb-doorlock`. Copy the code from the `config.lua` file provided in the downloaded package and paste it at the end of your existing `qb-doorlock/config.lua`.
7.  Add the NFT car model names to your `resources/[qb]/qb-core/shared/vehicles.lua` file (copy from the provided `vehicles.lua`).

### Option 3: NFT Cars & Houses (New ps-housing User)

If you are setting up NFT cars and houses and do **not** currently use `ps-housing`:

1.  **Install Dependencies & Base ps-housing:** You first need to set up `ps-housing` and its dependencies.
    *   (Optional) You can just watch [this tutorial](https://www.youtube.com/watch?v=yBb4RF9vNt4) for a visual guide on the original `ps-housing` setup:
    *   **Or read the [official `ps-housing` documentation](https://github.com/Project-Sloth/ps-housing)** for dependencies and the standard installation process:
    *   **Crucially:** When the instructions tell you to add the `ps-housing` and `ps-realtor` folders and run the SQL, use the **modified** `ps-housing` and `ps-realtor` folders and the `properties.sql` file provided in **our download package**, not the original ones.
6.  To run the provided `properties.sql` script against your database.
    *   Open HeidiSQL and connect to your database.
    *   Click "File" -> "Load SQL file...".
    *   Select the `properties.sql` file from the download package.
    *   Click the "Execute SQL" button (looks like a blue play icon, or press F9).
    *   This script adds table and property data (locations, doors, images, descriptions, etc.) to your database.
2.  **Add NFTconnect & Assets:** Once the base (modified) `ps-housing` is working, place the `[MLOs]`, `[shells]`, `store`, `NFTconnect`, and `cars` folders into your server's `resources` directory.
3.  **Ensure Resources:** Ensure `NFTconnect`, `store`, `[MLOs]`, `[shells]`, and `cars` are started in your `server.cfg` *after* the modified `ps-housing` and its dependencies.
5.  **Configure Doorlock:** Open the `config.lua` file located in your `resources/[qb]/qb-doorlock`. Copy the code from the `config.lua` file provided in the downloaded package and paste it at the end of your existing `qb-doorlock/config.lua`.
6.  **Add Vehicles:** Add the NFT car model names to your `resources/[qb]/qb-core/shared/vehicles.lua` file (copy from the provided `vehicles.lua`).

## How It Works

NFTconnect securely communicates with our central server to validate player NFTs and determine asset ownership based on those NFTs. However, all logic for controlling access to the in-game assets (cars, houses) remains on your server. NFTconnect simply provides the verified ownership data for your server resources (like the modified `ps-housing`) to execute upon.

## Support

If you encounter any issues during setup or have questions, please visit [Discord](https://discord.gg/7dr9m5AFCF) or see [website](https://pixly.games/nftconnect) for contact information:

If you'd like to include your assets in our NFT marketplace or if you already see them listed — please reach out. We have several programs that may interest you.
