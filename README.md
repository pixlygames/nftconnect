# NFTconnect for FiveM (QBcore Framework)

NFTconnect enables FiveM server owners using the QBcore framework to easily integrate an in-game marketplace for NFT-based assets like houses and cars. Players connect their crypto wallets, and the NFTs they own automatically appear in-game, granting access to unique assets.

**Server owners earn 40% of every NFT sale made through the marketplace on their server.**

Watch the DEMO: https://www.youtube.com/watch?v=qtUUVqL1xOs

## Overview

This solution consists of several components:

*   **NFTconnect Script**: Handles NFT validation and communication.
*   **Modified ps-housing**: An enhanced version of the popular housing script to support NFT properties.
*   **Modified ps-realtor**: Works with the modified `ps-housing` for property management.
*   **Assets**: Includes MLOs, Shells, car models, and the store UI (`[MLOs]`, `[shells]`, `cars`, `store` folders).
*   **Files to add data for cars and houses**: Includes config.lua, properties_import.sql, properties.sql, vehicles.lua.

**Download all required files here (GitHub has file limits):** https://drive.google.com/drive/folders/1aIIiMnsWhIjrdhCZY1IKlKUtcU6fYy2f?usp=sharing

## Configuration (Mandatory)

**IMPORTANT:** Before starting, you **MUST** configure the `NFTconnect` script with your public TON/Telegram wallet address. This takes about 30 seconds. Watch how: [https://www.youtube.com/watch?v=NYM9D2hg8Hw](https://www.youtube.com/watch?v=NYM9D2hg8Hw)

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

1.  Place the `[MLOs]`, `[shells]`, and `store` folders into your server's `resources` directory.
2.  **Remove** your existing `ps-housing` and `ps-realtor` resource folders.
3.  Place the **modified** `ps-housing` and `ps-realtor` folders (provided in the download package) into your `resources` directory.
4.  Place the `NFTconnect` and `cars` folders into your `resources` directory.
5.  Ensure `NFTconnect`, `store`, `[MLOs]`, `[shells]`, `cars`, and the **modified** `ps-housing` and `ps-realtor` are started in your `server.cfg`. Remember to respect the original `ps-housing` dependencies and start order (e.g., `ox_lib`, `ps-realtor`, `ps-housing`).
6.  Run the provided `properties_import.sql` script against your database.
    *   Open HeidiSQL and connect to your database.
    *   Click "File" -> "Load SQL file...".
    *   Select the `properties_import.sql` file from the download package.
    *   Click the "Execute SQL" button (looks like a blue play icon, or press F9).
    *   This script adds property data (locations, doors, images, descriptions, etc.) to your existing `properties` table. It starts adding properties from `property_id` 1001 onwards, so it should not affect existing properties unless you already have over 1000 properties defined.
7.  Open the `config.lua` file located in `resources/[qb]/qb-doorlock`. Copy the code from the `config.lua` file provided in the `qb-doorlock` folder of the download package and paste it at the end of your existing `qb-doorlock/config.lua`.
8.  Add the NFT car model names to your `resources/[qb]/qb-core/shared/vehicles.lua` file (copy from the provided `vehicles.lua`).

### Option 3: NFT Cars & Houses (New ps-housing User)

If you are setting up NFT cars and houses and do **not** currently use `ps-housing`:

1.  **Install Dependencies & Base ps-housing:** You first need to set up `ps-housing` and its dependencies.
    *   (Optional) You can jst watch this tutorial for a visual guide on the original `ps-housing` setup: https://www.youtube.com/watch?v=yBb4RF9vNt4
    *   **Or read the official `ps-housing` documentation** for dependencies and the standard installation process: https://github.com/Project-Sloth/ps-housing
    *   **Crucially:** When the instructions tell you to add the `ps-housing` and `ps-realtor` folders and run the SQL, use the **modified** `ps-housing` and `ps-realtor` folders and the `properties.sql` file provided in **our download package**, not the original ones.
6.  To run the provided `properties.sql` script against your database.
    *   Open HeidiSQL and connect to your database.
    *   Click "File" -> "Load SQL file...".
    *   Select the `properties.sql` file from the download package.
    *   Click the "Execute SQL" button (looks like a blue play icon, or press F9).
    *   This script adds table and property data (locations, doors, images, descriptions, etc.) to your database.
2.  **Add NFTconnect & Assets:** Once the base (modified) `ps-housing` is working, place the `[MLOs]`, `[shells]`, `store`, `NFTconnect`, and `cars` folders into your server's `resources` directory.
3.  **Ensure Resources:** Ensure `NFTconnect`, `store`, `[MLOs]`, `[shells]`, and `cars` are started in your `server.cfg` *after* the modified `ps-housing` and its dependencies.
5.  **Configure Doorlock:** Open the `config.lua` file located in `resources/[qb]/qb-doorlock`. Copy the code from the `config.lua` file provided in the `qb-doorlock` folder of the download package and paste it at the end of your existing `qb-doorlock/config.lua`.
6.  **Add Vehicles:** Add the NFT car model names to your `resources/[qb]/qb-core/shared/vehicles.lua` file (copy from the provided `vehicles.lua`).

## How It Works

NFTconnect securely communicates with our central server to validate player NFTs and determine asset ownership based on those NFTs. However, all logic for controlling access to the in-game assets (cars, houses) remains on your server. NFTconnect simply provides the verified ownership data for your server resources (like the modified `ps-housing`) to execute upon.

## Support

If you encounter any issues during setup or have questions, please visit our website for contact information:
https://pixly.games/nftconnect
