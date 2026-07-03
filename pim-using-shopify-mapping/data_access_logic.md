# Data Access Logic — NotNaked PIM

This document covers Part 2 (generic CRUD against the PIM database) and
Part 3 (Shopify integration) pseudo-code, as required by the assignment.
Table and column names reference `create_tables.sql`.

---

## Part 2 — Core PIM Data Access Logic

### 2.1 Create a new product

```
function createProduct(input):
    # 1. Validate required fields
    if input.name is null or trim(input.name) == "":
        throw ValidationError("Product name is required")

    if input.sku is not null:
        existing = findVariantsBySKU(input.sku)
        if existing is not empty:
            # SKU is not the primary key, but we still warn on create
            logDataQualityIssue("DUPLICATE_SKU", "VARIANT", null, { "sku": input.sku })

    # 2. Begin transaction
    beginTransaction()

    try:
        productId = INSERT INTO product (name, description_html, handle, status,
                                          product_type, vendor, product_level_gtin)
                    VALUES (input.name, input.descriptionHtml, input.handle, input.status,
                            input.productType, input.vendor, input.gtin)

        for each optionInput in input.options:
            optionId = INSERT INTO product_option (product_id, name, position)
                       VALUES (productId, optionInput.name, optionInput.position)
            for each value in optionInput.values:
                INSERT INTO product_option_value (product_option_id, value, position)
                VALUES (optionId, value.value, value.position)

        for each variantInput in input.variants:
            createVariantForProduct(productId, variantInput)  # see below, reused by update flow

        commitTransaction()
        return productId

    catch error:
        rollbackTransaction()
        throw error
```

### 2.2 Retrieve a product by identifier

```
function getProductBySkuOrId(identifier):
    # identifier can be a PIM product id, a Shopify GID, or a SKU
    if isNumeric(identifier):
        product = SELECT * FROM product WHERE id = identifier AND is_active = true
    else if identifier starts with "gid://shopify/Product/":
        product = SELECT * FROM product WHERE shopify_id = identifier AND is_active = true
    else:
        # Treat as SKU lookup — go through variant, since SKU lives on variant
        variant = SELECT * FROM product_variant WHERE sku = identifier AND is_active = true LIMIT 1
        if variant is null:
            return null
        product = SELECT * FROM product WHERE id = variant.product_id

    if product is null:
        return null

    product.options  = SELECT * FROM product_option WHERE product_id = product.id
    product.variants = SELECT * FROM product_variant WHERE product_id = product.id AND is_active = true
    product.media    = SELECT * FROM product_media WHERE product_id = product.id
    product.tags     = SELECT tag FROM product_tag WHERE product_id = product.id

    return product
```

### 2.3 Update an existing product

```
function updateProduct(productId, input):
    beginTransaction()
    try:
        UPDATE product
        SET name = input.name,
            description_html = input.descriptionHtml,
            handle = input.handle,
            status = input.status,
            product_type = input.productType,
            vendor = input.vendor,
            product_level_gtin = input.gtin
        WHERE id = productId

        # Options/values: simplest correct approach is diff-and-replace
        existingOptionIds = SELECT id FROM product_option WHERE product_id = productId
        DELETE FROM product_option WHERE product_id = productId  # cascades to option_value

        for each optionInput in input.options:
            optionId = INSERT INTO product_option (...) VALUES (...)
            for each value in optionInput.values:
                INSERT INTO product_option_value (...) VALUES (...)

        # Variants: update if exists (by shopify_id or pim id), else create
        for each variantInput in input.variants:
            existingVariant = findVariantByShopifyId(variantInput.shopifyId)
            if existingVariant exists:
                updateVariant(existingVariant.id, variantInput)
            else:
                createVariantForProduct(productId, variantInput)

        # Variants present in DB but absent from input are archived, not hard-deleted
        currentVariantIds = SELECT id FROM product_variant WHERE product_id = productId AND is_active = true
        incomingShopifyIds = set of variantInput.shopifyId for variantInput in input.variants
        for each v in currentVariantIds:
            if v.shopify_id not in incomingShopifyIds:
                archiveVariant(v.id, reason = "REMOVED_FROM_SOURCE")

        commitTransaction()
    catch error:
        rollbackTransaction()
        throw error
```

### 2.4 Delete (archive) a product

```
function deleteProduct(productId, hard = false):
    if not hard:
        # Preferred path — soft delete, see Part 3 deletion handling for the
        # Shopify-driven version of this.
        now = currentTimestamp()
        UPDATE product SET is_active = false, archived_at = now, archive_reason = "MANUAL_ARCHIVE"
        WHERE id = productId
        UPDATE product_variant SET is_active = false, archived_at = now WHERE product_id = productId
        UPDATE inventory_item SET is_active = false, archived_at = now
        WHERE variant_id IN (SELECT id FROM product_variant WHERE product_id = productId)
        return

    # Hard delete — reserved for retention jobs / explicit admin action
    beginTransaction()
    try:
        DELETE FROM product_attribute WHERE product_id = productId
        DELETE FROM inventory_item_detail WHERE inventory_item_id IN (
            SELECT id FROM inventory_item WHERE variant_id IN (
                SELECT id FROM product_variant WHERE product_id = productId))
        DELETE FROM inventory_item WHERE variant_id IN (
            SELECT id FROM product_variant WHERE product_id = productId)
        DELETE FROM product_variant_option_value WHERE variant_id IN (
            SELECT id FROM product_variant WHERE product_id = productId)
        DELETE FROM product_variant WHERE product_id = productId
        DELETE FROM product_media WHERE product_id = productId
        DELETE FROM product_option WHERE product_id = productId  # cascades to option_value
        DELETE FROM product_tag WHERE product_id = productId
        DELETE FROM product_category_member WHERE product_id = productId
        DELETE FROM product WHERE id = productId
        commitTransaction()
    catch error:
        rollbackTransaction()
        throw error
```

---

## Part 3 — Shopify Integration

### 3.1 Fetch product data (online, paginated)

Admin GraphQL 2026-07 query used for both single-product refresh and
paginated sync:

```graphql
query SyncProductsForPIM($first: Int!, $after: String) {
  products(first: $first, after: $after) {
    edges {
      cursor
      node {
        id
        title
        descriptionHtml
        handle
        status
        productType
        vendor
        tags
        options { name position values }
        variants(first: 50) {
          edges {
            node {
              id
              title
              sku
              barcode
              price { amount currencyCode }
              compareAtPrice { amount currencyCode }
              inventoryItem {
                id
                sku
                inventoryLevels(first: 50) {
                  edges {
                    node {
                      id
                      location { id name }
                      quantities(names: ["available"]) { name quantity updatedAt }
                    }
                  }
                }
              }
              selectedOptions { name value }
            }
          }
        }
        gtin: metafield(key: "gtin") { id key jsonValue }
        attributes: metafield(key: "attributes") { id key jsonValue }
      }
    }
    pageInfo { hasNextPage }
  }
}
```

Required scopes: `read_products`, `read_inventory`, `read_locations`.

```
function fetchProductsFromShopify(afterCursor = null, pageSize = 50):
    variables = { "first": pageSize, "after": afterCursor }
    response = executeGraphQLWithRetry(SyncProductsForPIM, variables)   # see 3.5
    return response.data.products

function syncAllProductsOnline():
    after = null
    do:
        productsConnection = fetchProductsFromShopify(after)
        for each edge in productsConnection.edges:
            processShopifyProductNode(edge.node)
        hasNext = productsConnection.pageInfo.hasNextPage
        after = productsConnection.edges[last].cursor
    while hasNext
```

### 3.2 Full initial sync via Bulk Operations

For the first catalog load, prefer `bulkOperationRunQuery` over paginated
online queries — it avoids rate-limit pressure entirely.

```graphql
mutation RunFullCatalogBulkSync {
  bulkOperationRunQuery(
    query: "query { products(first: 250) { edges { node { id title descriptionHtml handle status productType vendor tags options { name position values } variants(first: 50) { edges { node { id title sku barcode price { amount currencyCode } compareAtPrice { amount currencyCode } inventoryItem { id sku inventoryLevels(first: 50) { edges { node { id location { id name } quantities(names: [\"available\"]) { name quantity updatedAt } } } } } selectedOptions { name value } } } } } } } }"
  ) {
    bulkOperation { id status url }
    userErrors { field message }
  }
}
```

```graphql
query CurrentBulkOp {
  currentBulkOperation {
    id status errorCode completedAt createdAt objectCount fileSize url partialDataUrl
  }
}
```

```
function startFullCatalogBulkSync():
    response = postGraphQL(RunFullCatalogBulkSync)
    payload = response.data.bulkOperationRunQuery
    if payload.userErrors is not empty:
        log(payload.userErrors); fail

    bulkOp = payload.bulkOperation
    INSERT INTO bulk_operation_log (shopify_bulk_op_id, status)
    VALUES (bulkOp.id, bulkOp.status)

    while true:
        sleep(POLL_INTERVAL_SECONDS)   # e.g. 5-10s
        current = postGraphQL(CurrentBulkOp).data.currentBulkOperation

        if current is null:
            log("No current bulk operation found"); break

        UPDATE bulk_operation_log SET status = current.status, object_count = current.objectCount,
                                       file_size = current.fileSize
        WHERE shopify_bulk_op_id = current.id

        if current.status == "COMPLETED":
            UPDATE bulk_operation_log SET result_url = current.url, completed_at = now()
            WHERE shopify_bulk_op_id = current.id
            downloadAndProcessJsonl(current.url)
            break
        else if current.status in ["FAILED", "CANCELED"]:
            log("Bulk sync failed", current.errorCode); break

function downloadAndProcessJsonl(url):
    response = HTTP_GET(url)
    if response.status_code != 200:
        log("Failed to download bulk file"); fail

    for each line in response.streamLines():
        if line is empty: continue
        obj = jsonParse(line)
        processBulkObject(obj)   # routes on obj.__typename, using __parentId to relink

function processBulkObject(obj):
    switch obj.__typename:
        case "Product":
            upsertProductFromNode(obj)
        case "ProductVariant":
            upsertVariantFromNode(obj, parentProductShopifyId = obj.__parentId)
        case "InventoryLevel":
            upsertInventoryDetailFromNode(obj)
        case "MediaImage":
            upsertMediaFromNode(obj, parentProductShopifyId = obj.__parentId)
```

### 3.3 Transform Shopify data → PIM structures

```
function transformShopifyProductNode(productNode):
    pimProduct = {
        "shopify_id": productNode.id,
        "name": productNode.title,
        "description_html": productNode.descriptionHtml,
        "handle": productNode.handle,
        "status": productNode.status,
        "product_type": productNode.productType,
        "vendor": productNode.vendor
    }

    pimTags = [ { "tag": t } for t in productNode.tags ]

    pimOptions = []
    pimOptionValues = []
    for each option in productNode.options:
        pimOptions.append({ "name": option.name, "position": option.position })
        for each value in option.values:
            pimOptionValues.append({ "option_name": option.name, "value": value })

    pimVariants = []
    for each edge in productNode.variants.edges:
        v = edge.node
        pimVariants.append({
            "shopify_id": v.id,
            "sku": v.sku,
            "gtin": v.barcode,
            "list_price_amount": decimal(v.price.amount),
            "list_price_currency": v.price.currencyCode,
            "compare_at_amount": v.compareAtPrice != null ? decimal(v.compareAtPrice.amount) : null,
            "compare_at_currency": v.compareAtPrice != null ? v.compareAtPrice.currencyCode : null,
            "inventory_item_shopify_id": v.inventoryItem.id,
            "selected_options": v.selectedOptions,
            "inventory_levels": v.inventoryItem.inventoryLevels.edges
        })

    productGtin = productNode.gtin != null ? jsonParse(productNode.gtin.jsonValue) : null
    productAttributesRaw = productNode.attributes  # metafield node, mapped in 3.4

    return {
        product: pimProduct, tags: pimTags, options: pimOptions,
        optionValues: pimOptionValues, variants: pimVariants,
        productGtin: productGtin, rawAttributesMetafield: productAttributesRaw
    }
```

### 3.4 Metafields → flexible attribute table

Product-level custom fields (GTIN, care instructions, material, etc.) are
defined as app-owned metafields under namespace `$app` and mapped into the
generic `product_attribute` table so new attributes never require a schema
change.

```
function mapMetafieldToAttribute(productPimId, variantPimId, metafieldNode):
    parsed = jsonParse(metafieldNode.jsonValue)

    attribute = {
        "product_id": productPimId,
        "variant_id": variantPimId,
        "source": "shopify_metafield",
        "namespace": metafieldNode.namespace ?? "$app",
        "attr_key": metafieldNode.key,
        "attr_type": metafieldNode.type,
        "value_raw": metafieldNode.jsonValue
    }

    if attribute.attr_type in ["single_line_text_field", "multi_line_text_field"]:
        attribute.value_text = parsed
    else if attribute.attr_type in ["number_integer", "number_decimal"]:
        attribute.value_number = parsed
    else if attribute.attr_type == "json":
        attribute.value_json = parsed

    return attribute

function syncProductGtinAndAttributes(productNode, pimProductId):
    if productNode.gtin is not null:
        gtinValue = jsonParse(productNode.gtin.jsonValue)
        UPDATE product SET product_level_gtin = gtinValue WHERE id = pimProductId
        attr = mapMetafieldToAttribute(pimProductId, null, productNode.gtin)
        upsertProductAttribute(attr)

    if productNode.attributes is not null:
        attr = mapMetafieldToAttribute(pimProductId, null, productNode.attributes)
        upsertProductAttribute(attr)
```

### 3.5 Rate limiting: retry with backoff on THROTTLED

```
function executeGraphQLWithRetry(query, variables, maxRetries = 5):
    attempt = 0
    while attempt <= maxRetries:
        response = HTTP_POST(adminGraphQLEndpoint, headers = authHeaders,
                              body = { "query": query, "variables": variables })

        if response.errors is empty:
            return response

        throttled = any(err.extensions?.code == "THROTTLED" for err in response.errors)
        if not throttled:
            log("GraphQL error", response.errors)
            throw GraphQLError(response.errors)

        throttle = response.extensions?.cost?.throttleStatus
        if throttle is not null:
            requestedCost = response.extensions.cost.requestedQueryCost
            deficit = requestedCost - throttle.currentlyAvailable
            delaySeconds = deficit <= 0 ? 1.0 : ceil(deficit / throttle.restoreRate) + 1.0
        else:
            delaySeconds = 3.0

        sleep(delaySeconds)
        attempt += 1

    throw MaxRetriesExceededError()
```

Design notes for the write-up: use `bulkOperationRunQuery` for the full
catalog load so the online rate limit is never a factor there; reserve
online paginated/single-product queries for incremental refreshes, where
this retry wrapper keeps calls safe.

### 3.6 Store transformed data (upsert)

```
function upsertProductGraph(transformed):
    beginTransaction()
    try:
        existing = SELECT id FROM product WHERE shopify_id = transformed.product.shopify_id
        if existing exists:
            productId = existing.id
            UPDATE product SET name=.., description_html=.., handle=.., status=..,
                                product_type=.., vendor=.. WHERE id = productId
        else:
            productId = INSERT INTO product (...) VALUES (transformed.product.*)

        DELETE FROM product_tag WHERE product_id = productId
        for each tag in transformed.tags:
            INSERT INTO product_tag (product_id, tag) VALUES (productId, tag.tag)

        DELETE FROM product_option WHERE product_id = productId   # cascades option_value
        optionValueIdByName = {}
        for each option in transformed.options:
            optionId = INSERT INTO product_option (product_id, name, position) VALUES (...)
            for each value in [ov for ov in transformed.optionValues if ov.option_name == option.name]:
                valueId = INSERT INTO product_option_value (product_option_id, value) VALUES (...)
                optionValueIdByName[(option.name, value.value)] = valueId

        for each variantInput in transformed.variants:
            processVariantForPIM(productId, variantInput, optionValueIdByName)  # 3.7 handles conflicts

        syncProductGtinAndAttributes(transformed, productId)   # 3.4

        commitTransaction()
    catch error:
        rollbackTransaction()
        throw error
```

### 3.7 Conflict handling: duplicate SKUs and missing barcodes

Shopify does not enforce SKU uniqueness or require a barcode — the PIM
must detect and flag these before writing, and must always key upserts
on the Shopify GID, never on SKU or barcode.

```
function processVariantForPIM(productPimId, variantInput, optionValueIdByName):
    shopifyVariantId = variantInput.shopify_id
    sku = variantInput.sku
    existingVariant = SELECT * FROM product_variant WHERE shopify_id = shopifyVariantId

    skuConflict = false
    if sku is null or sku == "":
        logDataQualityIssue("MISSING_SKU", "VARIANT", shopifyVariantId, {})
    else:
        conflicting = SELECT * FROM product_variant
                       WHERE sku = sku AND shopify_id != shopifyVariantId AND is_active = true
        if conflicting is not empty:
            skuConflict = true
            logDataQualityIssue("DUPLICATE_SKU", "VARIANT", shopifyVariantId, { "sku": sku })

    barcode = variantInput.gtin
    if barcode is null or barcode == "":
        logDataQualityIssue("MISSING_BARCODE", "VARIANT", shopifyVariantId, { "sku": sku })
    else if not isValidGTIN(barcode):
        logDataQualityIssue("INVALID_BARCODE", "VARIANT", shopifyVariantId, { "barcode": barcode })

    variantRow = {
        "product_id": productPimId, "shopify_id": shopifyVariantId, "sku": sku, "gtin": barcode,
        "list_price_amount": variantInput.list_price_amount,
        "list_price_currency": variantInput.list_price_currency,
        "compare_at_amount": variantInput.compare_at_amount,
        "compare_at_currency": variantInput.compare_at_currency,
        "inventory_item_shopify_id": variantInput.inventory_item_shopify_id,
        "sku_conflict": skuConflict
    }

    if existingVariant exists:
        variantId = existingVariant.id
        UPDATE product_variant SET ... WHERE id = variantId
    else:
        variantId = INSERT INTO product_variant (...) VALUES (variantRow.*)

    DELETE FROM product_variant_option_value WHERE variant_id = variantId
    for each selected in variantInput.selected_options:
        valueId = optionValueIdByName[(selected.name, selected.value)]
        INSERT INTO product_variant_option_value (variant_id, option_value_id) VALUES (variantId, valueId)

    syncInventoryForVariant(variantId, variantInput)   # see 3.8
    return variantId
```

### 3.8 Inventory per location

```
function syncInventoryForVariant(variantPimId, variantInput):
    existingItem = SELECT * FROM inventory_item WHERE variant_id = variantPimId
    if existingItem exists:
        inventoryItemId = existingItem.id
    else:
        inventoryItemId = INSERT INTO inventory_item (shopify_id, variant_id, sku)
                           VALUES (variantInput.inventory_item_shopify_id, variantPimId, variantInput.sku)

    for each levelEdge in variantInput.inventory_levels:
        level = levelEdge.node
        for each qty in level.quantities:
            existingDetail = SELECT * FROM inventory_item_detail
                              WHERE inventory_item_id = inventoryItemId
                                AND location_shopify_id = level.location.id
                                AND state_name = qty.name
            if existingDetail exists:
                UPDATE inventory_item_detail SET quantity = qty.quantity, updated_at = qty.updatedAt
                WHERE id = existingDetail.id
            else:
                INSERT INTO inventory_item_detail
                    (inventory_item_id, location_shopify_id, location_name, state_name, quantity, updated_at)
                VALUES (inventoryItemId, level.location.id, level.location.name, qty.name, qty.quantity, qty.updatedAt)
```

### 3.9 Incremental sync via webhooks

Full initial load uses bulk operations (3.2); ongoing changes are
event-driven via `products/create`, `products/update`, and
`products/delete` webhooks. Webhook payloads are REST JSON and are
treated only as change signals — the canonical data is always re-fetched
via GraphQL before being written to the PIM.

```
function handleProductWebhook(requestBody, headers):
    topic = headers["X-Shopify-Topic"]
    payload = jsonParse(requestBody)

    if topic == "products/delete":
        handleProductDeleted(payload)
    else if topic in ["products/create", "products/update"]:
        handleProductUpsert(payload)

function handleProductUpsert(payload):
    graphQlId = payload.admin_graphql_api_id
    productNode = fetchProductForPIMById(graphQlId)   # single-product variant of SyncProductsForPIM
    transformed = transformShopifyProductNode(productNode)
    upsertProductGraph(transformed)

function fetchProductForPIMById(graphQlProductId):
    response = executeGraphQLWithRetry(ProductForPIM, { "id": graphQlProductId })
    if response.errors is not empty:
        log("GraphQL error fetching product", graphQlProductId, response.errors)
        throw GraphQLError(response.errors)
    return response.data.product
```

### 3.10 Deletion handling: soft delete vs hard delete

```
function handleProductDeleted(payload):
    graphQlId = payload.admin_graphql_api_id
    pimProduct = SELECT * FROM product WHERE shopify_id = graphQlId

    if pimProduct is null:
        log("Deletion webhook for unknown product", graphQlId)
        return

    archivePimProduct(pimProduct.id, reason = "SHOPIFY_DELETED")

function archivePimProduct(pimProductId, reason):
    now = currentTimestamp()
    UPDATE product SET is_active = false, archived_at = now, archive_reason = reason WHERE id = pimProductId
    UPDATE product_variant SET is_active = false, archived_at = now WHERE product_id = pimProductId
    UPDATE inventory_item SET is_active = false, archived_at = now
    WHERE variant_id IN (SELECT id FROM product_variant WHERE product_id = pimProductId)

function reconcileDeletedProductsFromBulk(shopifyProductIdsSet):
    # Safety net for missed webhooks: run periodically after a fresh
    # bulk/paginated product-ID snapshot.
    activeProducts = SELECT id, shopify_id FROM product WHERE is_active = true
    for each p in activeProducts:
        if p.shopify_id not in shopifyProductIdsSet:
            archivePimProduct(p.id, reason = "MISSING_IN_SHOPIFY_SNAPSHOT")

function hardDeleteArchivedProducts(cutoffDate):
    # Retention job — not driven by webhooks. Run on a schedule.
    toDelete = SELECT id FROM product
               WHERE is_active = false AND archived_at < cutoffDate
                 AND archive_reason IN ("SHOPIFY_DELETED", "MANUAL_ARCHIVE", "MISSING_IN_SHOPIFY_SNAPSHOT")
    for each productId in toDelete:
        deleteProduct(productId, hard = true)   # reuses 2.4
```
