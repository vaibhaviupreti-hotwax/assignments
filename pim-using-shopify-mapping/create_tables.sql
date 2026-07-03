-- =====================================================================
-- NotNaked PIM System — Database Schema (MySQL, UDM-aligned)
-- =====================================================================
-- This schema is designed to be UDM-compliant while mapping cleanly
-- onto Shopify's Admin GraphQL (2026-07) Product model. Every table
-- that has a Shopify counterpart stores the Shopify GID in a
-- `shopify_id` column so that Shopify's global ID remains the
-- canonical key for upsert/sync operations (never SKU or barcode,
-- since Shopify does not guarantee uniqueness on either).
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- Table: product
-- Core product record. One row per Shopify Product.
-- ---------------------------------------------------------------------
CREATE TABLE product (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    shopify_id          VARCHAR(64)  NOT NULL COMMENT 'Full Shopify GID, e.g. gid://shopify/Product/123',
    name                VARCHAR(255) NOT NULL COMMENT 'Maps to Shopify Product.title',
    description_html    TEXT             NULL COMMENT 'Maps to Shopify Product.descriptionHtml',
    handle              VARCHAR(255)     NULL COMMENT 'Maps to Shopify Product.handle (storefront URL slug)',
    status              VARCHAR(20)      NULL COMMENT 'Maps to Shopify Product.status (ACTIVE/DRAFT/ARCHIVED)',
    product_type        VARCHAR(100)     NULL COMMENT 'Maps to Shopify Product.productType',
    vendor              VARCHAR(150)     NULL COMMENT 'Maps to Shopify Product.vendor',
    product_level_gtin  VARCHAR(64)      NULL COMMENT 'From app metafield $app:gtin, kept as a dedicated indexed column for fast lookup',
    is_active           TINYINT(1)   NOT NULL DEFAULT 1 COMMENT 'FALSE when soft-deleted/archived',
    archived_at         DATETIME         NULL COMMENT 'Timestamp when product was archived',
    archive_reason      VARCHAR(50)      NULL COMMENT 'e.g. SHOPIFY_DELETED, MISSING_IN_SHOPIFY_SNAPSHOT, MANUAL_ARCHIVE',
    created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_product_shopify_id (shopify_id),
    KEY idx_product_gtin (product_level_gtin),
    KEY idx_product_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Core PIM product entity, 1:1 with Shopify Product';

-- ---------------------------------------------------------------------
-- Table: product_tag
-- Many tags per product (Shopify Product.tags is a string array).
-- ---------------------------------------------------------------------
CREATE TABLE product_tag (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED NOT NULL,
    tag         VARCHAR(150) NOT NULL,
    UNIQUE KEY uq_product_tag (product_id, tag),
    CONSTRAINT fk_product_tag_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Flattened Shopify Product.tags array, one row per tag';

-- ---------------------------------------------------------------------
-- Table: product_category
-- NotNaked's own catalog taxonomy (independent of Shopify's model).
-- Self-referencing to allow hierarchical categories.
-- ---------------------------------------------------------------------
CREATE TABLE product_category (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name                VARCHAR(150) NOT NULL,
    parent_category_id  BIGINT UNSIGNED NULL COMMENT 'Self-FK for category hierarchy/rollup',
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_category_parent FOREIGN KEY (parent_category_id) REFERENCES product_category(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Catalog taxonomy for organizing products, hierarchical via parent_category_id';

-- ---------------------------------------------------------------------
-- Table: product_category_member
-- Many-to-many link between products and categories.
-- ---------------------------------------------------------------------
CREATE TABLE product_category_member (
    product_id   BIGINT UNSIGNED NOT NULL,
    category_id  BIGINT UNSIGNED NOT NULL,
    is_primary   TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Marks the primary/default category for the product',
    PRIMARY KEY (product_id, category_id),
    CONSTRAINT fk_pcm_product  FOREIGN KEY (product_id)  REFERENCES product(id)          ON DELETE CASCADE,
    CONSTRAINT fk_pcm_category FOREIGN KEY (category_id) REFERENCES product_category(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Many-to-many association between products and categories';

-- ---------------------------------------------------------------------
-- Table: product_option
-- Maps to Shopify Product.options (e.g. "Color", "Size").
-- ---------------------------------------------------------------------
CREATE TABLE product_option (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED NOT NULL,
    name        VARCHAR(100) NOT NULL COMMENT 'e.g. Color, Size, Material',
    position    INT UNSIGNED NOT NULL DEFAULT 0,
    UNIQUE KEY uq_product_option (product_id, name),
    CONSTRAINT fk_product_option_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Product-level option definitions, e.g. Color/Size';

-- ---------------------------------------------------------------------
-- Table: product_option_value
-- Maps to Shopify Product.options[].values[] (e.g. "Red", "Blue").
-- ---------------------------------------------------------------------
CREATE TABLE product_option_value (
    id                BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_option_id BIGINT UNSIGNED NOT NULL,
    value             VARCHAR(150) NOT NULL,
    position          INT UNSIGNED NOT NULL DEFAULT 0,
    UNIQUE KEY uq_option_value (product_option_id, value),
    CONSTRAINT fk_option_value_option FOREIGN KEY (product_option_id) REFERENCES product_option(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Individual selectable values belonging to a product option';

-- ---------------------------------------------------------------------
-- Table: product_variant
-- Maps to Shopify ProductVariant. Prices stored as DECIMAL + ISO
-- currency code pairs (never FLOAT), since Shopify Money fields
-- serialize amount as a string to preserve precision.
-- ---------------------------------------------------------------------
CREATE TABLE product_variant (
    id                     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id             BIGINT UNSIGNED NOT NULL,
    shopify_id             VARCHAR(64)  NOT NULL COMMENT 'Shopify ProductVariant GID',
    title                  VARCHAR(255)     NULL,
    sku                    VARCHAR(100)     NULL COMMENT 'Shopify does not enforce uniqueness; see sku_conflict flag',
    gtin                   VARCHAR(64)      NULL COMMENT 'Maps to Shopify ProductVariant.barcode (UPC/EAN/GTIN), optional',
    list_price_amount      DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'ProductVariant.price.amount',
    list_price_currency    CHAR(3)      NOT NULL DEFAULT 'USD' COMMENT 'ProductVariant.price.currencyCode (ISO 4217)',
    compare_at_amount      DECIMAL(18,2)    NULL COMMENT 'ProductVariant.compareAtPrice.amount',
    compare_at_currency    CHAR(3)          NULL COMMENT 'ProductVariant.compareAtPrice.currencyCode',
    cost_amount            DECIMAL(18,2)    NULL COMMENT 'Internal cost, not sourced from Shopify storefront-facing fields',
    cost_currency          CHAR(3)          NULL,
    inventory_item_shopify_id VARCHAR(64)   NULL COMMENT 'Shopify InventoryItem GID, bridges to inventory_item table',
    sku_conflict           TINYINT(1)   NOT NULL DEFAULT 0 COMMENT 'TRUE when this SKU collides with another variant; flagged for merch review',
    is_active              TINYINT(1)   NOT NULL DEFAULT 1,
    archived_at            DATETIME         NULL,
    created_at             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_variant_shopify_id (shopify_id),
    KEY idx_variant_sku (sku),
    KEY idx_variant_product (product_id),
    CONSTRAINT fk_variant_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Product variants (SKU-level records), 1:1 with Shopify ProductVariant';

-- ---------------------------------------------------------------------
-- Table: product_variant_option_value
-- Maps to Shopify ProductVariant.selectedOptions — links a variant to
-- the specific option values that describe it (e.g. Color=Red, Size=L).
-- ---------------------------------------------------------------------
CREATE TABLE product_variant_option_value (
    variant_id       BIGINT UNSIGNED NOT NULL,
    option_value_id  BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (variant_id, option_value_id),
    CONSTRAINT fk_pvov_variant FOREIGN KEY (variant_id)      REFERENCES product_variant(id)      ON DELETE CASCADE,
    CONSTRAINT fk_pvov_option_value FOREIGN KEY (option_value_id) REFERENCES product_option_value(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Join table: which option value(s) each variant represents';

-- ---------------------------------------------------------------------
-- Table: product_media
-- Maps to Shopify Product.media (MediaImage nodes).
-- ---------------------------------------------------------------------
CREATE TABLE product_media (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED NOT NULL,
    shopify_id  VARCHAR(64)  NOT NULL COMMENT 'Shopify MediaImage GID',
    url         VARCHAR(1024) NOT NULL COMMENT 'CDN URL, MediaImage.image.url',
    alt_text    VARCHAR(255)     NULL COMMENT 'MediaImage.alt',
    media_type  VARCHAR(30)  NOT NULL DEFAULT 'IMAGE',
    position    INT UNSIGNED NOT NULL DEFAULT 0,
    UNIQUE KEY uq_media_shopify_id (shopify_id),
    KEY idx_media_product (product_id),
    CONSTRAINT fk_media_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Product images/media sourced from Shopify media union';

-- ---------------------------------------------------------------------
-- Table: inventory_item
-- Maps to Shopify InventoryItem, 1:1 with a variant.
-- ---------------------------------------------------------------------
CREATE TABLE inventory_item (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    shopify_id  VARCHAR(64)  NOT NULL COMMENT 'Shopify InventoryItem GID',
    variant_id  BIGINT UNSIGNED NOT NULL,
    sku         VARCHAR(100)     NULL COMMENT 'InventoryItem.sku (may duplicate variant.sku)',
    is_active   TINYINT(1)   NOT NULL DEFAULT 1,
    archived_at DATETIME         NULL,
    UNIQUE KEY uq_inventory_item_shopify_id (shopify_id),
    UNIQUE KEY uq_inventory_item_variant (variant_id),
    CONSTRAINT fk_inventory_item_variant FOREIGN KEY (variant_id) REFERENCES product_variant(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Physical inventory item record, 1:1 with a variant';

-- ---------------------------------------------------------------------
-- Table: inventory_item_detail
-- Maps to Shopify InventoryLevel/InventoryQuantity — per-location,
-- per-state (available/on_hand/committed) quantity breakdown.
-- ---------------------------------------------------------------------
CREATE TABLE inventory_item_detail (
    id                 BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    inventory_item_id  BIGINT UNSIGNED NOT NULL,
    location_shopify_id VARCHAR(64) NOT NULL COMMENT 'Shopify Location GID',
    location_name      VARCHAR(150)    NULL,
    state_name         VARCHAR(30) NOT NULL COMMENT 'available | on_hand | committed | etc. (InventoryQuantity.name)',
    quantity           INT NOT NULL DEFAULT 0,
    updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_inv_detail (inventory_item_id, location_shopify_id, state_name),
    CONSTRAINT fk_inv_detail_item FOREIGN KEY (inventory_item_id) REFERENCES inventory_item(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Master-detail: quantity of an inventory item at a specific location and state';

-- ---------------------------------------------------------------------
-- Table: product_attribute
-- Flexible EAV-style table for Shopify metafields and other custom
-- attributes, so new attributes can be added without schema changes.
-- Scoped to either a product OR a variant (not both).
-- ---------------------------------------------------------------------
CREATE TABLE product_attribute (
    id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id   BIGINT UNSIGNED NULL,
    variant_id   BIGINT UNSIGNED NULL,
    source       VARCHAR(30)  NOT NULL DEFAULT 'shopify_metafield' COMMENT 'Origin of this attribute',
    namespace    VARCHAR(64)  NOT NULL COMMENT 'Metafield namespace, e.g. $app',
    attr_key     VARCHAR(100) NOT NULL COMMENT 'Metafield key, e.g. gtin, attributes',
    attr_type    VARCHAR(50)      NULL COMMENT 'Shopify metafield type, e.g. single_line_text_field, json',
    value_raw    TEXT             NULL COMMENT 'Raw jsonValue exactly as returned by Shopify',
    value_text   VARCHAR(500)     NULL COMMENT 'Normalized text value when attr_type is text-like',
    value_number DECIMAL(18,4)    NULL COMMENT 'Normalized numeric value when attr_type is numeric',
    value_json   JSON             NULL COMMENT 'Normalized JSON value when attr_type is json',
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_attr_product (product_id, namespace, attr_key),
    KEY idx_attr_variant (variant_id, namespace, attr_key),
    CONSTRAINT fk_attr_product FOREIGN KEY (product_id) REFERENCES product(id)         ON DELETE CASCADE,
    CONSTRAINT fk_attr_variant FOREIGN KEY (variant_id) REFERENCES product_variant(id) ON DELETE CASCADE,
    CONSTRAINT chk_attr_owner CHECK (
        (product_id IS NOT NULL AND variant_id IS NULL) OR
        (product_id IS NULL AND variant_id IS NOT NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Flexible attribute store for Shopify metafields and other custom fields';

-- ---------------------------------------------------------------------
-- Table: data_quality_log
-- Records conflicts/anomalies detected during sync (duplicate SKU,
-- missing barcode, invalid GTIN, etc.) for merch team review.
-- ---------------------------------------------------------------------
CREATE TABLE data_quality_log (
    id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    issue_type   VARCHAR(50)  NOT NULL COMMENT 'e.g. MISSING_SKU, DUPLICATE_SKU, MISSING_BARCODE, INVALID_BARCODE, DUPLICATE_PRODUCT_GTIN',
    entity_type  VARCHAR(30)  NOT NULL COMMENT 'PRODUCT | VARIANT',
    shopify_id   VARCHAR(64)      NULL COMMENT 'Related Shopify GID, if available',
    context_json JSON             NULL COMMENT 'Free-form details captured at detection time',
    resolved     TINYINT(1)   NOT NULL DEFAULT 0,
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_dql_type (issue_type),
    KEY idx_dql_resolved (resolved)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Audit log of data-quality issues found while syncing from Shopify';

-- ---------------------------------------------------------------------
-- Table: bulk_operation_log
-- Tracks Shopify bulkOperationRunQuery runs used for full catalog sync.
-- ---------------------------------------------------------------------
CREATE TABLE bulk_operation_log (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    shopify_bulk_op_id      VARCHAR(64)  NOT NULL COMMENT 'Shopify BulkOperation GID',
    status                  VARCHAR(20)  NOT NULL COMMENT 'CREATED | RUNNING | COMPLETED | FAILED | CANCELED',
    object_count            BIGINT UNSIGNED NULL,
    file_size               BIGINT UNSIGNED NULL,
    result_url              VARCHAR(1024)   NULL COMMENT 'Signed JSONL download URL when COMPLETED',
    started_at              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at            DATETIME         NULL,
    UNIQUE KEY uq_bulk_op_shopify_id (shopify_bulk_op_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Tracks full-catalog bulk sync operations against the Shopify Admin API';

SET FOREIGN_KEY_CHECKS = 1;
