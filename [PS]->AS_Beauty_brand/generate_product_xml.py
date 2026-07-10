import csv
import xml.etree.ElementTree as ET
from xml.dom import minidom
import os

def generate_xml():
    csv_file = 'julep_products.csv'
    xml_file = 'data/ASBeautyProductData.xml'
    
    root = ET.Element('entity-facade-xml', type='ext-seed')
    
    # 1. Add Julep Products from CSV
    if os.path.exists(csv_file):
        with open(csv_file, mode='r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                sku = row.get('product-sku')
                name = row.get('product-name')
                price = row.get('list-price')
                shopify_id_str = row.get('attributes', '')
                
                # We need a SKU and a name to create a valid product
                if not sku or not name:
                    continue
                    
                # Extract additional fields
                long_desc = row.get('long-description', '').strip()
                brand = row.get('brand-name', '').strip()
                charge_shipping = row.get('charge-shipping', '').strip()
                taxable = row.get('taxable', '').strip()
                
                # Build product attributes dynamically to omit empty ones
                prod_attrs = {
                    'productId': sku,
                    'productTypeId': 'FINISHED_GOOD',
                    'internalName': name,
                    'productName': name
                }
                if long_desc: prod_attrs['longDescription'] = long_desc
                if brand: prod_attrs['brandName'] = brand
                if charge_shipping: prod_attrs['chargeShipping'] = charge_shipping
                if taxable: prod_attrs['taxable'] = taxable

                # Create Product entity
                product = ET.SubElement(root, 'org.apache.ofbiz.product.product.Product', **prod_attrs)
                
                # Nested ProductPrice
                if price:
                    ET.SubElement(product, 'org.apache.ofbiz.product.price.ProductPrice',
                                  productPriceTypeId='LIST_PRICE',
                                  productPricePurposeId='PURCHASE',
                                  currencyUomId='USD',
                                  productStoreGroupId='_NA_',
                                  fromDate='2026-01-01 00:00:00.0',
                                  price=price)
                
                # Nested GoodIdentification for SKU
                ET.SubElement(product, 'org.apache.ofbiz.product.product.GoodIdentification',
                              goodIdentificationTypeId='SKU',
                              idValue=sku)
                
                # Extract Shopify Product ID from attributes if present (e.g., SHOPIFY_PROD_ID:8843020402711)
                if 'SHOPIFY_PROD_ID:' in shopify_id_str:
                    shopify_id = shopify_id_str.split('SHOPIFY_PROD_ID:')[1].split('|')[0]
                    if shopify_id:
                        ET.SubElement(product, 'org.apache.ofbiz.product.product.GoodIdentification',
                                      goodIdentificationTypeId='SHOPIFY_PROD_ID',
                                      idValue=shopify_id)
                
                # Nested ProductFacility
                ET.SubElement(product, 'org.apache.ofbiz.product.facility.ProductFacility',
                              facilityId='AS_BEAUTY_WH')
                              
                # Nested ProductCategoryMember
                ET.SubElement(product, 'org.apache.ofbiz.product.category.ProductCategoryMember',
                              productCategoryId='BROWSE_ROOT',
                              fromDate='2026-01-01 00:00:00.0')
                              
                # Nested InventoryItem
                ET.SubElement(product, 'org.apache.ofbiz.product.inventory.InventoryItem',
                              inventoryItemId='INV_'+sku,
                              productId=sku,
                              facilityId='AS_BEAUTY_WH',
                              inventoryItemTypeId='NON_SERIAL_INV_ITEM',
                              availableToPromiseTotal='1000',
                              accountingQuantityTotal='1000')
                              
    # 2. Add Mock Laura Geller Products
    mock_lg_products = [
        {"sku": "LG-BAKED-BALANCE", "name": "Baked Balance-n-Brighten Color Correcting Foundation", "price": "34.00", "shopify_id": "LG123456789"},
        {"sku": "LG-SPACKLE-PRIMER", "name": "Spackle Skin Perfecting Primer: Hydrating", "price": "32.00", "shopify_id": "LG987654321"},
        {"sku": "LG-ITALIAN-MARBLE", "name": "Italian Marble Lipstick", "price": "21.00", "shopify_id": "LG456123789"}
    ]
    
    for row in mock_lg_products:
        sku = row["sku"]
        product = ET.SubElement(root, 'org.apache.ofbiz.product.product.Product', 
                                productId=sku, 
                                productTypeId='FINISHED_GOOD', 
                                internalName=row["name"], 
                                productName=row["name"])
        
        ET.SubElement(product, 'org.apache.ofbiz.product.price.ProductPrice',
                      productPriceTypeId='LIST_PRICE',
                      productPricePurposeId='PURCHASE',
                      currencyUomId='USD',
                      productStoreGroupId='_NA_',
                      fromDate='2026-01-01 00:00:00.0',
                      price=row["price"])
                      
        ET.SubElement(product, 'org.apache.ofbiz.product.product.GoodIdentification',
                      goodIdentificationTypeId='SKU',
                      idValue=sku)
                      
        ET.SubElement(product, 'org.apache.ofbiz.product.product.GoodIdentification',
                      goodIdentificationTypeId='SHOPIFY_PROD_ID',
                      idValue=row["shopify_id"])
                      
        ET.SubElement(product, 'org.apache.ofbiz.product.facility.ProductFacility',
                      facilityId='AS_BEAUTY_WH')
                      
        ET.SubElement(product, 'org.apache.ofbiz.product.category.ProductCategoryMember',
                      productCategoryId='BROWSE_ROOT',
                      fromDate='2026-01-01 00:00:00.0')
                      
        ET.SubElement(product, 'org.apache.ofbiz.product.inventory.InventoryItem',
                      inventoryItemId='INV_'+sku,
                      productId=sku,
                      facilityId='AS_BEAUTY_WH',
                      inventoryItemTypeId='NON_SERIAL_INV_ITEM',
                      availableToPromiseTotal='1000',
                      accountingQuantityTotal='1000')

    # Convert to string and format
    xml_str = ET.tostring(root, encoding='utf-8')
    parsed_xml = minidom.parseString(xml_str)
    pretty_xml = parsed_xml.toprettyxml(indent="    ")
    
    # Remove empty lines caused by minidom
    pretty_xml = '\n'.join([line for line in pretty_xml.split('\n') if line.strip()])

    with open(xml_file, "w", encoding='utf-8') as f:
        f.write(pretty_xml)
        
    print(f"Successfully generated {xml_file} with {len(root)} products.")

if __name__ == '__main__':
    generate_xml()
