# Shopify Product API → NotNaked PIM Mapping

Source: Admin GraphQL API, version **2026-07**. All tables/columns
referenced below are defined in `create_tables.sql`.

---

## 1. Core Product

| Shopify (`Product`) field | PIM table.column | Notes |
|---|---|---|
| `id` | `product.shopify_id` | Full GID (`gid://shopify/Product/123`), stored as-is — never truncated to the numeric suffix. This is the canonical key for every upsert. |
| `title` | `product.name` | Required. |
| `descriptionHtml` | `product.description_html` | Kept as HTML for direct rendering. |
| `productType` | `product.product_type` | Free text from Shopify; NotNaked's own taxonomy lives separately in `product_category`. |
| `vendor` | `product.vendor` | |
| `status` | `product.status` | Enum: `ACTIVE`, `DRAFT`, `ARCHIVED`. |
| `tags` (`[String!]`) | `product_tag` (one row per tag) | Multi-valued field, flattened into a child table rather than a delimited string, so tags can be indexed/queried individually. |
| `handle` | `product.handle` | Storefront URL slug. |
| `metafield(key: "gtin")` | `product.product_level_gtin` (+ `product_attribute` row) | App-owned metafield, namespace `$app`. Stored both as a dedicated indexed column (fast lookup) and as a generic attribute row (audit trail). |
| `metafield(key: "attributes")` | `product_attribute` row (`attr_type = "json"`) | Arbitrary JSON blob of extra attributes (material, care instructions, etc.) — kept flexible so new fields don't require schema changes. |

## 2. Product Options and Variations

Shopify separates *option definitions* (`Product.options`) from the
*values a specific variant selects* (`ProductVariant.selectedOptions`).
The PIM mirrors that split.

| Shopify field | PIM table.column | Notes |
|---|---|---|
| `Product.options[].name` | `product_option.name` | e.g. `Color`, `Size`. |
| `Product.options[].position` | `product_option.position` | Display order. |
| `Product.options[].values[]` | `product_option_value.value` | One row per selectable value, e.g. `Red`, `Blue`. |
| `ProductVariant.selectedOptions[]` | `product_variant_option_value` (join table) | Links a variant to the exact `(option, value)` pairs that describe it — e.g. `Color=Red`, `Size=L`. |

**Transformation example** — a Shopify product with:
```json
"options": [
  { "name": "Color", "values": ["Red", "Blue"] },
  { "name": "Size", "values": ["S", "M"] }
]
```
produces 2 `product_option` rows and 4 `product_option_value` rows. A
variant with `selectedOptions: [{"name":"Color","value":"Red"},{"name":"Size","value":"M"}]`
gets 2 rows in `product_variant_option_value`, pointing at the `Red` and
`M` option-value records.

## 3. Product Variants

| Shopify (`ProductVariant`) field | PIM table.column | Notes |
|---|---|---|
| `id` | `product_variant.shopify_id` | GID; canonical key, never SKU. |
| `title` | `product_variant.title` | |
| `sku` | `product_variant.sku` | **Not unique in Shopify.** See §6 for conflict handling; PIM flags collisions via `sku_conflict` rather than rejecting them. |
| `barcode` | `product_variant.gtin` | Holds UPC/EAN/GTIN. Optional — may be null. |
| `price` | `product_variant.list_price_amount` + `list_price_currency` | See §5, Money handling. |
| `compareAtPrice` | `product_variant.compare_at_amount` + `compare_at_currency` | Nullable — Shopify returns `null` if not set. |
| `inventoryItem.id` | `product_variant.inventory_item_shopify_id` + `inventory_item.shopify_id` | Bridges to inventory tracking (§4). |

## 4. Inventory

| Shopify field | PIM table.column | Notes |
|---|---|---|
| `InventoryItem.id` | `inventory_item.shopify_id` | 1:1 with a variant. |
| `InventoryItem.sku` | `inventory_item.sku` | May duplicate `product_variant.sku`. |
| `InventoryLevel.location.id` | `inventory_item_detail.location_shopify_id` | One row per (item, location, state). |
| `InventoryLevel.location.name` | `inventory_item_detail.location_name` | |
| `InventoryQuantity.name` (from `quantities(names: [...])`) | `inventory_item_detail.state_name` | e.g. `available`, `on_hand`, `committed`. |
| `InventoryQuantity.quantity` | `inventory_item_detail.quantity` | |
| `InventoryQuantity.updatedAt` | `inventory_item_detail.updated_at` | |

Query path: `Product → variants → inventoryItem → inventoryLevels → quantities`.
The PIM stores one detail row per `(inventory_item, location, state)` so
multiple states (`available` vs `on_hand` vs `committed`) can be tracked
side by side without widening the schema.

## 5. Money / Pricing

In Admin GraphQL 2026-07, `price` and `compareAtPrice` on `ProductVariant`
are **Money objects**, not plain strings:

```json
{ "amount": "19.99", "currencyCode": "USD" }
```

`amount` is serialized as a string to preserve decimal precision.
`currencyCode` is a 3-letter ISO 4217 code.

| Shopify | PIM | Notes |
|---|---|---|
| `price.amount` | `product_variant.list_price_amount` (`DECIMAL(18,2)`) | Never stored as `FLOAT`/`DOUBLE` — avoids rounding drift. |
| `price.currencyCode` | `product_variant.list_price_currency` (`CHAR(3)`) | |
| `compareAtPrice.amount` | `product_variant.compare_at_amount` | Nullable. |
| `compareAtPrice.currencyCode` | `product_variant.compare_at_currency` | Nullable; matches `list_price_currency` in single-currency stores, but the PIM does not hardcode this assumption. |

## 6. Media

| Shopify (`MediaImage`) field | PIM table.column | Notes |
|---|---|---|
| `id` | `product_media.shopify_id` | GID. |
| `image.url` | `product_media.url` | CDN URL. |
| `alt` | `product_media.alt_text` | |
| (query position) | `product_media.position` | Display order. |

Uses the `media`/`MediaImage` union rather than the deprecated `images`
field.

## 7. Custom Attributes (Metafields)

App-owned metafields are defined under namespace `$app` (via
`shopify.app.toml`) and mapped into the generic `product_attribute`
table so NotNaked can add new custom fields without altering the schema.

| Shopify | PIM | Notes |
|---|---|---|
| `metafield.namespace` | `product_attribute.namespace` | Typically `$app`. |
| `metafield.key` | `product_attribute.attr_key` | e.g. `gtin`, `attributes`. |
| `metafield.type` | `product_attribute.attr_type` | e.g. `single_line_text_field`, `json`. |
| `metafield.jsonValue` | `product_attribute.value_raw` (+ normalized `value_text`/`value_number`/`value_json`) | Raw value preserved as-is; a typed column is also populated based on `attr_type` for efficient querying. |

Product-level GTIN is double-mapped: once into the dedicated, indexed
`product.product_level_gtin` column (fast lookups), and once into
`product_attribute` (audit trail / consistency with other metafields).

## 8. Handling Multi-valued and Type-Differing Fields — Summary

- **`tags` (string array)** → flattened to `product_tag`, one row per tag, unique per `(product_id, tag)`.
- **`options`/`values` (nested array)** → split into `product_option` + `product_option_value`, two levels deep.
- **`variants` (array of objects)** → own table `product_variant`, keyed by Shopify GID.
- **`selectedOptions` (array on each variant)** → many-to-many join `product_variant_option_value`.
- **`media` (union/array)** → own table `product_media`.
- **Money objects (`price`, `compareAtPrice`)** → split into a `DECIMAL` amount column and a `CHAR(3)` currency column, rather than a single string.
- **Metafields (arbitrary key/value)** → generic EAV-style `product_attribute` table, so the schema doesn't need to change as new custom fields are added.

## 9. Sync Strategy Summary

- **Full initial load:** `bulkOperationRunQuery` with the same product query, polled via `currentBulkOperation`, result streamed from the returned JSONL URL.
- **Incremental updates:** `products/create`/`products/update` webhooks act as change signals only; the canonical product is always re-fetched via GraphQL (by `admin_graphql_api_id`) before being upserted.
- **Deletions:** `products/delete` webhook triggers a soft delete (`is_active = false`, `archived_at`, `archive_reason = 'SHOPIFY_DELETED'`); a periodic snapshot diff (`MISSING_IN_SHOPIFY_SNAPSHOT`) acts as a safety net for missed webhooks; hard delete is reserved for a separate retention job.
- **Rate limits:** every response's `extensions.cost.throttleStatus` is inspected; `THROTTLED` errors trigger a backoff computed from `currentlyAvailable`/`restoreRate` before retrying. Bulk operations sidestep this entirely for the initial load.
- **Data quality:** duplicate SKUs and missing/invalid barcodes never block a sync — they are written with a flag (`sku_conflict`) or left null, and logged to `data_quality_log` for merch review. Shopify GIDs, not SKU/barcode, are always the upsert key.
