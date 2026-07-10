# AS Beauty Multi-Brand Setup Guide (Moqui Framework)

This repository component (`as-beauty-maarg`) contains the architecture, data definitions, and automation scripts required to set up a multi-brand environment (Julep and Laura Geller) within the Moqui/HotWax framework.

This guide provides a flawless, step-by-step onboarding process for any new developer looking to replicate, maintain, or extend this architecture.

## Overview
The architecture is designed to allow multiple independent Shopify storefronts to operate under a single, unified `ProductStore` and `Facility`. This minimizes configuration overhead while keeping order routing and inventory unified.

## Prerequisites & Installation
If you are receiving this component folder to set up the system from scratch:
1. You must have a working instance of the **Moqui Framework**.
2. Drop this entire `as-beauty-maarg` folder directly into your `moqui-framework/runtime/component/` directory.
3. Moqui will automatically detect it on the next boot.

## Step-by-Step Implementation Guide

### Step 1: Component Registration
Because Moqui auto-detects components, the main requirement is that the seed data is registered inside this folder's `component.xml`.
- **File:** `component.xml`
- **Action:** Ensure your XML data files are registered under the `<entity-facade>` tag with `type="ext-seed"`.
```xml
<entity-facade>
    <load-data location="component://as-beauty-maarg/data/ASBeautySetupData.xml" type="ext-seed"/>
    <load-data location="component://as-beauty-maarg/data/ASBeautyLocationData.xml" type="ext-seed"/>
    <load-data location="component://as-beauty-maarg/data/ASBeautyProductData.xml" type="ext-seed"/>
</entity-facade>
```

### Step 2: Define Core Architecture (The Pillars)
Define the core relationships in `ASBeautySetupData.xml` and `ASBeautyLocationData.xml`.
- **Party:** Create the `AS_BEAUTY` internal organization.
- **Facility:** Create `AS_BEAUTY_WH` to act as the central inventory repository.
- **Contact:** Map Postal Addresses and Telecom numbers to the Party and the Facility.
- **Catalog:** Map the `DUMMY_CATALOG` to the existing `BROWSE_ROOT` category.
- **Store:** Create `AS_BEAUTY_STORE` and link the Facility and Catalog to it.
- **Shopify Integration:** Map the two distinct Shopify shops (`JULEP_SHOP`, `LAURA_GELLER_SHOP`) directly to the `AS_BEAUTY_STORE`.

### Step 3: Generate Product & Inventory Data
Because creating XML manually for hundreds of products is error-prone, use the included Python automation script.
- **File:** `generate_product_xml.py`
- **Action:** Run the script to parse `julep_products.csv` and generate `ASBeautyProductData.xml`.
```bash
cd runtime/component/as-beauty-maarg
python3 generate_product_xml.py
```
*Note: The script dynamically injects `ProductCategoryMember` (for catalog visibility) and `InventoryItem` (for stock availability) for every single SKU.*

### Step 4: Load the Data
Moqui's Entity Engine handles data loading using an "Upsert" logic. It only strictly requires primary keys.
- **Action:** Run the data loader from the `moqui-framework` root.
```bash
java -jar moqui.war load types=ext-seed
```
This will cleanly insert/update over 5,500 records.

### Step 5: Restart the Server
Once the data is loaded, clear the entity cache by restarting the server to see the changes immediately in the UI.
```bash
./gradlew run
```

---

## Entities Populated

This setup populates exactly 25 distinct entity tables across 5 core pillars:

1. **Party:** `Party`, `PartyGroup`, `PartyRole`
2. **Contact:** `ContactMech`, `PostalAddress`, `TelecomNumber`, `PartyContactMech`, `PartyContactMechPurpose`, `FacilityContactMech`, `FacilityContactMechPurpose`
3. **Store:** `Facility`, `ProductStore`, `ProductStoreFacility`, `ProductStoreSetting`, `ProductStoreCatalog`, `ShopifyShop`, `IntegrationTypeMapping`
4. **Catalog:** `ProdCatalog`, `ProdCatalogCategory`
5. **Product:** `Product`, `ProductPrice`, `GoodIdentification`, `ProductFacility`, `ProductCategoryMember`, `InventoryItem`

---

## Challenges Faced & Resolutions

When building this setup, we encountered several architectural challenges. Here is how they were resolved to ensure a flawless setup for future developers:

### 1. Legacy Sandbox Contamination
**Challenge:** Initially, the system attempted to reference entity definitions and code from a deprecated `/sandbox/` folder, causing class path and mapping failures.
**Resolution:** We strictly isolated the architecture to use **Moqui-native entity definitions** (`entity-definition-3.xsd`). If a class or entity cannot be found inside `moqui-framework/runtime/component/`, it should not be used.

### 2. Shopify Shop Mapping Failures
**Challenge:** The old OFBiz legacy model attempted to map `ShopifyShop` to a `ShopifyConfig` entity, throwing Foreign Key constraint errors.
**Resolution:** Audited the `ShopifyConnectorEntitymodel.xml` and discovered that the modern Moqui architecture maps `ShopId` directly to `ProductStoreId`. Removing the middleman fixed the FK constraints.

### 3. Products Not Visible in the UI Catalog
**Challenge:** Products were successfully loaded into the database but did not appear in the storefront UI when browsing.
**Resolution:** The `PRIMARY_PRODUCT_CATEGORY_ID` on the `Product` table is a shortcut, but Moqui structurally relies on the `ProductCategoryMember` join table. We updated the Python script to map every product to the `BROWSE_ROOT` category, making them discoverable.

### 4. "Out of Stock" Errors During Order Simulation
**Challenge:** Products existed, but placing test orders failed due to 0 Available to Promise (ATP) inventory.
**Resolution:** Added an `InventoryItem` block inside the Python script to automatically mint 1,000 units of ATP and Accounting Quantity for every SKU upon generation, ensuring immediate sellability for testing.
