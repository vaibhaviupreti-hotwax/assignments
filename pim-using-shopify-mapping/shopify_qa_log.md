# Shopify Assistant Q&A Log — NotNaked PIM Assignment

Reference log of all questions asked to the Shopify dev-assistant tool and
its answers, for Part 3 (Shopify integration) of the PIM assignment.
API version referenced throughout: **Admin GraphQL 2026-07**.

---

## 1. Inventory quantities per location

**Q:** Give me the GraphQL fields to fetch `inventoryLevel` quantities per
location for each variant's `inventoryItem`, and show how to map that
into an `InventoryItem`/`InventoryItemDetail` structure.

**A:**
Path: `Product → variants → inventoryItem → inventoryLevels → quantities(names: [...])`.

Validated query:
```graphql
query VariantInventoryPerLocation($firstProducts: Int!, $afterProduct: String) {
  products(first: $firstProducts, after: $afterProduct) {
    edges {
      cursor
      node {
        id
        title
        variants(first: 50) {
          edges {
            node {
              id
              sku
              inventoryItem {
                id
                sku
                inventoryLevels(first: 50) {
                  edges {
                    node {
                      id
                      location { id name }
                      quantities(names: ["available"]) {
                        id
                        name
                        quantity
                        updatedAt
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```
Required scopes: `read_products`, `read_inventory`, `read_locations`.

To discover which quantity states exist for a store:
```graphql
query InventoryQuantityNames {
  inventoryProperties {
    quantityNames { name isInUse }
  }
}
```

**Mapping pattern:**
- `InventoryItem` → holds `inventory_item_id` (GID), `variant_id`, `sku`.
- `InventoryItemDetail` → one row per `(inventory_item, location, state)`, holding `location_id`, `location_name`, `state_name`, `quantity`, `updated_at`.

**Transform pseudo-code:**
```
for each productEdge in response.data.products.edges:
    product = productEdge.node
    for each variantEdge in product.variants.edges:
        variant = variantEdge.node
        invItemNode = variant.inventoryItem
        upsertInventoryItem({ inventory_item_id: invItemNode.id, variant_id: variant.id, sku: invItemNode.sku or variant.sku })
        for each levelEdge in invItemNode.inventoryLevels.edges:
            level = levelEdge.node
            for each qty in level.quantities:
                upsertInventoryItemDetail({
                    inventory_item_id: invItemNode.id,
                    location_id: level.location.id,
                    location_name: level.location.name,
                    state_name: qty.name,
                    quantity: qty.quantity,
                    updated_at: qty.updatedAt
                })
```
Alternative: a "columns-per-state" row layout (one row per location with
`available_quantity`, `on_hand_quantity`, `committed_quantity` columns)
was also offered as a UDM design choice — same source fields either way.

---

## 2. Money / currency handling

**Q:** Show the exact JSON shape of `price`/`compareAtPrice` in the
2026-07 API (are they plain strings or MoneyV2 objects with
amount+currencyCode?) and how I should store that in a decimal +
currency column pair.

**A:**
`price` and `compareAtPrice` on `ProductVariant` are **Money objects**,
not plain strings:
```json
{ "amount": "19.99", "currencyCode": "USD" }
```
`amount` is a string (preserves decimal precision); `currencyCode` is a
3-letter ISO 4217 code.

Example full response shape:
```json
{
  "data": {
    "products": {
      "edges": [{
        "node": {
          "id": "gid://shopify/Product/123",
          "title": "Example Product",
          "variants": {
            "edges": [{
              "node": {
                "id": "gid://shopify/ProductVariant/456",
                "sku": "SKU-001",
                "price": { "amount": "19.99", "currencyCode": "USD" },
                "compareAtPrice": { "amount": "24.99", "currencyCode": "USD" }
              }
            }]
          }
        }
      }]
    }
  }
}
```
`compareAtPrice` can be `null`.

**Storage recommendation:** `DECIMAL(18,2)` amount column + `CHAR(3)`
currency column (never `FLOAT`/`DOUBLE`, to avoid rounding errors).
Suggested columns: `list_price_amount`, `list_price_currency`,
`compare_at_amount`, `compare_at_currency`.

**Transform pseudo-code:**
```
priceObj = variantNode.price
compareObj = variantNode.compareAtPrice  # may be null

list_price_amount = decimal(priceObj.amount)
list_price_currency = priceObj.currencyCode

if compareObj is not null:
    compare_at_amount = decimal(compareObj.amount)
    compare_at_currency = compareObj.currencyCode
else:
    compare_at_amount = null
    compare_at_currency = null
```
Never hardcode currency — always take it from `currencyCode`, even if a
single-currency store is assumed.

---

## 3. Bulk operations for full catalog sync

**Q:** For a full initial sync (not incremental), give me the
`bulkOperationRunQuery` mutation using the same product query, and
pseudo-code for polling `currentBulkOperation` and downloading the JSONL
result.

**A:**
Bulk operations run a full query async and return a signed JSONL file
URL; `products(first: 250)` inside a bulk query is auto-paginated by
Shopify — no manual cursor loop needed.

```graphql
mutation RunFullCatalogBulkSync {
  bulkOperationRunQuery(
    query: """
      query SyncProductsForPIM {
        products(first: 250) {
          edges {
            cursor
            node {
              id title descriptionHtml handle status productType vendor tags
              options { name position values }
              variants(first: 50) {
                edges {
                  node {
                    id title sku barcode
                    price { amount currencyCode }
                    compareAtPrice { amount currencyCode }
                    inventoryItem {
                      id sku
                      inventoryLevels(first: 50) {
                        edges { node { id location { id name } quantities(names: ["available"]) { name quantity updatedAt } } }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    """
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

**Polling pseudo-code:**
```
function startFullCatalogBulkSync():
    response = postGraphQL(RunFullCatalogBulkSync)
    payload = response.data.bulkOperationRunQuery
    if payload.userErrors is not empty: fail

    bulkOp = payload.bulkOperation
    while true:
        sleep(POLL_INTERVAL_SECONDS)  # 5-10s
        current = postGraphQL(CurrentBulkOp).data.currentBulkOperation
        if current is null: fail or break
        if current.status == "COMPLETED":
            if current.url is null: fail
            else: downloadAndProcessJsonl(current.url); break
        elif current.status in ["FAILED", "CANCELED"]:
            log "failed", current.errorCode; break
```

**Downloading/processing JSONL:**
```
function downloadAndProcessJsonl(url):
    response = HTTP_GET(url)
    for each line in response.streamLines():
        if line is empty: continue
        obj = jsonParse(line)
        processBulkObject(obj)

function processBulkObject(obj):
    switch obj.__typename:
        case "Product": upsertProduct(...)
        case "ProductVariant": upsertVariant({ product_shopify_id: obj.__parentId, ... })
        case "InventoryLevel": upsertInventoryDetail(...)
```
Each JSONL line includes `__typename` (routes to the right handler) and
`__parentId` (links child objects like variants back to their parent
product). Exact flattening details depend on Shopify's bulk JSONL format
docs.

---

## 4. Rate limits / cost

**Q:** What's the query cost for this products query with 50 variants
nested, and how should my pseudo-code handle `THROTTLED` errors — retry
with backoff based on `extensions.cost.throttleStatus`?

**A:**
No fixed cost number exists in the abstract — cost depends on
`first` page sizes and nested connection sizes, and is only known by
inspecting `extensions.cost.actualQueryCost` on an actual response.
Larger `first` on `products` and each nested connection
(`variants`, `inventoryLevels`, `media`) increases cost. Bulk operations
have a separate cost system managed by Shopify's bulk engine — no manual
throttling needed there.

**Response shape:**
```json
{
  "data": { "...": "..." },
  "extensions": {
    "cost": {
      "requestedQueryCost": 123,
      "actualQueryCost": 98,
      "throttleStatus": {
        "maximumAvailable": 1000,
        "currentlyAvailable": 902,
        "restoreRate": 50
      }
    }
  }
}
```
On throttle, `errors` includes `{"extensions": {"code": "THROTTLED"}}`
and `throttleStatus.currentlyAvailable` drops (often to 0).

**Backoff math:** `waitSeconds = ceil((requestedCost - currentlyAvailable) / restoreRate)`.

**Retry pseudo-code:**
```
function executeGraphQLWithRetry(query, variables, maxRetries = 5):
    attempt = 0
    while attempt <= maxRetries:
        response = HTTP_POST(...)
        if response.errors is empty: return response

        throttled = any(err.extensions?.code == "THROTTLED" for err in response.errors)
        if not throttled: throw response.errors

        throttle = response.extensions?.cost?.throttleStatus
        if throttle is not null:
            deficit = response.extensions.cost.requestedQueryCost - throttle.currentlyAvailable
            delaySeconds = deficit <= 0 ? 1.0 : ceil(deficit / throttle.restoreRate) + 1.0
        else:
            delaySeconds = 3.0
        sleep(delaySeconds)
        attempt += 1
    throw MaxRetriesExceededError()
```
Recommended strategy: use bulk operations for full sync (sidesteps
online rate limits entirely), and smaller paginated queries + this retry
wrapper for incremental/online calls.

---

## 5. Metafields — custom attributes (e.g. product-level GTIN)

**Q:** If NotNaked needs custom fields like GTIN at product level (not
just variant barcode) or custom attributes, how do I query metafields
and what's the pseudo-code to map a metafield namespace/key/value into a
flexible PIM attribute table?

**A:**
Best practice: define app-owned metafields in `shopify.app.toml` under
namespace `$app` (not written via ad-hoc mutations).

```toml
[product.metafields.app.gtin]
type = "single_line_text_field"
name = "Product GTIN"
access.admin = "merchant_read_write"

[product.metafields.app.attributes]
type = "json"
name = "Additional Attributes"
access.admin = "merchant_read_write"
```

**Query single named metafields:**
```graphql
query ProductWithCustomMetafields($id: ID!) {
  product(id: $id) {
    id title
    gtin: metafield(key: "gtin") { id key jsonValue }
    attributes: metafield(key: "attributes") { id key jsonValue }
  }
}
```

**Query all app metafields generically:**
```graphql
query ProductAllAppMetafields($id: ID!) {
  product(id: $id) {
    id
    metafields(namespace: "$app", first: 50) {
      edges { node { id namespace key type jsonValue } }
    }
  }
}
```
`jsonValue` is always preferred over `value` for consistent typed
handling — a text metafield returns a JSON-encoded string, a `json`-type
metafield returns the actual object/array.

**Flexible attribute table concept:** `product_attribute` with columns
`product_id`, `source`, `namespace`, `key`, `type`, `value_raw`, plus
optional normalized `value_text`/`value_number`/`value_json`.

**Mapping pseudo-code:**
```
function mapMetafieldToAttribute(productPimId, metafieldNode):
    namespace = metafieldNode.namespace
    key = metafieldNode.key
    type = metafieldNode.type
    parsed = jsonParse(metafieldNode.jsonValue)

    attribute = { product_id: productPimId, source: "shopify_metafield",
                  namespace: namespace, key: key, type: type,
                  value_raw: metafieldNode.jsonValue }

    if type in ["single_line_text_field", "multi_line_text_field"]:
        attribute.value_text = parsed
    elif type in ["number_integer", "number_decimal"]:
        attribute.value_number = parsed
    elif type == "json":
        attribute.value_json = parsed
    return attribute
```
Product-level GTIN can be special-cased: stored both as a dedicated
indexed column on `product` (fast lookup) and as a generic attribute row
(audit trail/consistency).

---

## 6. Incremental sync / webhooks

**Q:** For ongoing sync after initial load, should I use
`products/update` webhooks instead of polling? Give me the webhook
payload shape and how it differs from the GraphQL query fields.

**A:**
Recommended pattern: **bulk initial load → event-driven deltas via
`products/*` webhooks → per-event GraphQL fetch to refresh that product.**
Webhooks are change *signals*, not the source of truth — polling is a
less efficient fallback.

**`products/update` payload (REST JSON, snake_case):**
```json
{
  "id": 1072481062,
  "title": "Burton Custom Freestyle 151",
  "body_html": "<strong>Good snowboard!</strong>",
  "vendor": "Burton",
  "product_type": "Snowboard",
  "handle": "burton-custom-freestyle-151",
  "status": "active",
  "tags": "Board, Snow",
  "variants": [{
    "id": 1070325053,
    "sku": "123456",
    "price": "19.99",
    "compare_at_price": null,
    "barcode": "0123456789012",
    "inventory_quantity": 10,
    "admin_graphql_api_id": "gid://shopify/ProductVariant/1070325053"
  }],
  "admin_graphql_api_id": "gid://shopify/Product/1072481062"
}
```

**Key differences vs GraphQL:**
- REST snake_case (`body_html`, `product_type`) vs GraphQL camelCase (`descriptionHtml`, `productType`).
- `price` is a plain string (no `currencyCode`) vs GraphQL's Money object.
- No inventory-by-location, no metafields, no media union in the webhook payload.
- Includes both numeric `id` and the bridging `admin_graphql_api_id` (GID).

**Handler pseudo-code:**
```
function handleProductWebhook(webhookPayload):
    graphQlId = webhookPayload.admin_graphql_api_id
    topic = readWebhookTopicFromHeaders()
    if topic == "products/delete":
        markProductDeletedInPIM(graphQlId); return
    productNode = fetchProductForPIMById(graphQlId)   # re-fetch canonical data via GraphQL
    transformed = transformGraphQLProductToPIM(productNode)
    upsertProductGraph(transformed)
```
Subscribe to `products/create`, `products/update`, `products/delete`.

---

## 7. Conflict/error cases

**Q:** What happens if two variants have the same SKU within Shopify
itself, or if `barcode` is null — how should the pseudo-code branch for
these edge cases before upsert?

**A:**
Shopify does **not** enforce uniqueness on `sku`, and `barcode` is
optional (may be null/empty) — both are data-quality concerns the PIM
must handle, not the platform.

**Rule:** always upsert keyed on Shopify GID; treat SKU/barcode as
secondary/business keys only.

**SKU handling pseudo-code:**
```
function processVariantForPIM(productPimId, variantNode):
    variantId = variantNode.id
    sku = variantNode.sku
    existingVariant = findVariantByShopifyId(variantId)

    if sku is null or sku == "":
        # key on Shopify ID only, log missing SKU
        logDataQualityIssue("MISSING_SKU", {...})
        upsert-by-shopify-id; return

    variantsWithSameSku = findVariantsBySKU(sku)
    if variantsWithSameSku is empty:
        upsert normally using sku as secondary key
    else:
        # conflict: import both, flag for review, never merge
        logDataQualityIssue("DUPLICATE_SKU", {...})
        upsert with a conflict flag set
```

**Barcode handling pseudo-code:**
```
function handleBarcodeForVariant(variantNode, pimVariantRecord):
    barcode = variantNode.barcode
    if barcode is null or barcode == "":
        pimVariantRecord.gtin = null
        logDataQualityIssue("MISSING_BARCODE", {...})
        return
    if not isValidGTIN(barcode):
        logDataQualityIssue("INVALID_BARCODE", {...})
        pimVariantRecord.gtin = barcode   # or null, design choice
        return
    pimVariantRecord.gtin = barcode
```
Product-level GTIN metafields get the same treatment (missing / invalid
/ duplicate-across-products all logged via `logDataQualityIssue`, never
silently dropped or silently merged).

**Design principles to document:** canonical ID is always the Shopify
GID; SKU/barcode conflicts are logged, not blocked; PIM keeps both
conflicting records so the merch team can resolve manually.

---

## 8. Deletion handling

**Q:** How do I detect a product was deleted in Shopify — is there a
`products/delete` webhook, or do I need to diff against the last full
sync? Give pseudo-code for marking PIM records as archived vs hard
delete.

**A:**
Primary signal: the **`products/delete` webhook** (proactive). A
periodic diff against a full/bulk snapshot is a secondary safety net for
missed webhooks, not the primary mechanism.

**`products/delete` payload:**
```json
{
  "id": 1072481062,
  "title": "Burton Custom Freestyle 151",
  "handle": "burton-custom-freestyle-151",
  "status": "active",
  "admin_graphql_api_id": "gid://shopify/Product/1072481062"
}
```
After deletion, `product(id: ...)` in GraphQL returns `null` — there's
nothing left to re-fetch, so the webhook payload itself is used directly.

**Soft-delete handler pseudo-code:**
```
function handleProductDeleted(payload):
    graphQlId = payload.admin_graphql_api_id
    pimProduct = findPimProductByShopifyId(graphQlId)
    if pimProduct is null: log("unknown product"); return
    archivePimProduct(pimProduct.id, reason = "SHOPIFY_DELETED")

function archivePimProduct(pimProductId, reason):
    now = currentTimestamp()
    UPDATE product SET is_active=false, archived_at=now, archive_reason=reason WHERE id=pimProductId
    UPDATE product_variant SET is_active=false, archived_at=now WHERE product_id=pimProductId
    UPDATE inventory_item SET is_active=false, archived_at=now WHERE product_id=pimProductId
    UPDATE product_media SET is_active=false, archived_at=now WHERE product_id=pimProductId
```

**Hard-delete (retention job, not webhook-driven):**
```
function hardDeleteArchivedProducts(cutoffDate):
    toDelete = SELECT id FROM product
               WHERE is_active=false AND archived_at < cutoffDate
                 AND archive_reason IN ("SHOPIFY_DELETED", "MANUAL_ARCHIVE")
    for each productId in toDelete:
        DELETE FROM product_variant WHERE product_id = productId
        DELETE FROM inventory_item WHERE product_id = productId
        DELETE FROM product_media WHERE product_id = productId
        DELETE FROM product_attribute WHERE product_id = productId
        DELETE FROM product WHERE id = productId
```

**Fallback diff-based detection:**
```
function reconcileDeletedProductsFromBulk(shopifyProductIdsSet):
    pimProducts = SELECT id, shopify_id FROM product WHERE is_active = true
    for each p in pimProducts:
        if p.shopify_id not in shopifyProductIdsSet:
            archivePimProduct(p.id, reason = "MISSING_IN_SHOPIFY_SNAPSHOT")
```
Run this periodically (e.g. daily/weekly) using a fresh bulk or paginated
snapshot of product IDs, to catch anything a dropped webhook missed.

**Recommended defaults:** soft delete (archive) is the default behavior
on `products/delete`; hard delete is reserved for a separate scheduled
retention job or explicit GDPR-style erasure request.
