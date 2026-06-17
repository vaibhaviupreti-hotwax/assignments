# Postman Automated Collection - Fulfillment API Documentation

> **Note:** All requests require Bearer Token Authorization. Obtain the token from the Inspect Window.

---

## 1. Get Orders (Solr Query)
**Request Name:** Get Orders from OMS  
**Method:** `GET`  
**Base URL:** `https://nextgen-oms.hotwax.io`  
**Endpoint:** `/api/solr-query`

### Query Parameters:
| Parameter | Value | Description |
|-----------|-------|-------------|
| `json` | `{"filter":"docType: ORDER AND ...","query":"(*:*)","params":{"rows":"10","sort":"orderDate asc"}}` | Solr query with filter and sorting |

### Authorization:
- Header: `Authorization: Bearer {TOKEN}`
- Token obtained from browser Inspect Window

### Response:
```json
{
  "response": {
    "docs": [
      {
        "orderId": "ORDER123",
        "orderDate": "2024-01-15",
        ...
      }
    ]
  }
}
```

---

## 2. Create Order Fulfillment Wave
**Request Name:** Create Fulfillment Wave  
**Method:** `POST`  
**Base URL:** `https://nextgen-maarg.hotwax.io`  
**Endpoint:** `/rest/s1/poorti/createOrderFulfillmentWave`

### Authorization:
- Header: `Authorization: Bearer {TOKEN}`

### Request Body (JSON):
```json
{
  "packageName": "A",
  "facilityId": "MAPLEWOOD",
  "shipmentMethodTypeId": "STANDARD",
  "statusId": "PICKLIST_ASSIGNED",
  "pickers": [
    {
      "partyId": "10043",
      "roleTypeId": "WAREHOUSE_PICKER"
    }
  ],
  "orderItems": []
}
```

### Response:
```json
{
  "picklistId": "M100325",
  "shipmentIds": ["M100363"]
}
```

---

## 3. Print Picklist (PDF)
**Request Name:** Generate Picklist PDF  
**Method:** `GET`  
**Base URL:** `https://nextgen-maarg.hotwax.io`  
**Endpoint:** `/fop/apps/pdf/PrintPicklist`

### Query Parameters:
| Parameter | Example | Description |
|-----------|---------|-------------|
| `picklistId` | `M100325` | ID of the picklist to print |

### Full URL Example:
```
https://nextgen-maarg.hotwax.io/fop/apps/pdf/PrintPicklist?picklistId=M100325
```

### Response:
- PDF file download

---

## 4. Get Shipment Picklists
**Request Name:** Retrieve Shipment Picklists  
**Method:** `GET`  
**Base URL:** `https://nextgen-maarg.hotwax.io`  
**Endpoint:** `/rest/s1/poorti/shipmentPicklists`

### Query Parameters:
| Parameter | Example | Description |
|-----------|---------|-------------|
| `originFacilityId` | `MAPLEWOOD` | Facility ID |
| `statusId` | `SHIPMENT_APPROVED` | Status filter |
| `shipmentMethodTypeId` | `STOREPICKUP` | Shipment method |
| `shipmentMethodTypeId_op` | `equals` | Operator for comparison |
| `shipmentMethodTypeId_not` | `Y` | Exclude matches |
| `pageIndex` | `0` | Page number (0-indexed) |
| `pageSize` | `50` | Number of records per page |

### Full URL Example:
```
https://nextgen-maarg.hotwax.io/rest/s1/poorti/shipmentPicklists?originFacilityId=MAPLEWOOD&statusId=SHIPMENT_APPROVED&shipmentMethodTypeId=STOREPICKUP&shipmentMethodTypeId_op=equals&shipmentMethodTypeId_not=Y&pageIndex=0&pageSize=50
```

### Response:
```json
{
  "count": 10,
  "picklists": [
    {
      "picklistId": "M100325",
      "facilityId": "MAPLEWOOD",
      "statusId": "SHIPMENT_APPROVED"
    }
  ]
}
```

---

## 5. Get Enums
**Request Name:** Retrieve Enum Values  
**Method:** `GET`  
**Base URL:** `https://nextgen-maarg.hotwax.io`  
**Endpoint:** `/rest/s1/admin/enums`

### Query Parameters:
| Parameter | Example | Description |
|-----------|---------|-------------|
| `parentTypeId` | `REPORT_AN_ISSUE, RPRT_NO_VAR_LOG` | Parent type IDs (can be multiple) |
| `parentTypeId_op` | `in` | Operator for multiple values |
| `pageSize` | `20` | Number of records per page |
| `orderByField` | `sequenceNum` | Field to sort by |

### Full URL Example:
```
https://nextgen-maarg.hotwax.io/rest/s1/admin/enums?parentTypeId=REPORT_AN_ISSUE&parentTypeId=RPRT_NO_VAR_LOG&parentTypeId_op=in&pageSize=20&orderByField=sequenceNum
```

### Response:
```json
{
  "enums": [
    {
      "enumId": "ENUM_001",
      "description": "Issue Type",
      "sequenceNum": 1
    }
  ]
}
```

---

## 6. Get Shipments
**Request Name:** Retrieve Shipments List  
**Method:** `GET`  
**Base URL:** `https://nextgen-maarg.hotwax.io`  
**Endpoint:** `/rest/s1/poorti/shipments`

### Query Parameters:
| Parameter | Example | Description |
|-----------|---------|-------------|
| `pageSize` | `10` | Number of records per page |
| `orderBy` | `orderDate` | Sort field |
| `shipmentTypeId` | `SALES_SHIPMENT` | Shipment type |
| `productStoreId` | `STORE` | Product store identifier |
| `originFacilityId` | `MAPLEWOOD` | Origin facility |
| `orderStatusId` | `ORDER_APPROVED` | Order status |
| `statusId` | `SHIPMENT_APPROVED` | Shipment status |

### Full URL Example:
```
https://nextgen-maarg.hotwax.io/rest/s1/poorti/shipments?pageSize=10&orderBy=orderDate&shipmentTypeId=SALES_SHIPMENT&productStoreId=STORE&originFacilityId=MAPLEWOOD&orderStatusId=ORDER_APPROVED&statusId=SHIPMENT_APPROVED
```

### Response:
```json
{
  "count": 10,
  "shipments": [
    {
      "shipmentId": "M100363",
      "originFacilityId": "MAPLEWOOD",
      "statusId": "SHIPMENT_APPROVED"
    }
  ]
}
```

---

## 7. Get Shipment Packages
**Request Name:** Retrieve Packages for Shipment  
**Method:** `GET`  
**Base URL:** `https://nextgen-maarg.hotwax.io`  
**Endpoint:** `/rest/s1/poorti/shipments/{shipmentId}/shipmentPackages`

### Path Parameters:
| Parameter | Example | Description |
|-----------|---------|-------------|
| `shipmentId` | `M100363` | ID of the shipment |

### Full URL Example:
```
https://nextgen-maarg.hotwax.io/rest/s1/poorti/shipments/M100363/shipmentPackages
```

### Response:
```json
{
  "packages": [
    {
      "shipmentPackageId": "PKG001",
      "shipmentId": "M100363",
      "weight": 5.5,
      "contents": []
    }
  ]
}
```

---

## 8. Pack Shipment
**Request Name:** Pack Items in Shipment  
**Method:** `POST`  
**Base URL:** `https://nextgen-maarg.hotwax.io`  
**Endpoint:** `/rest/s1/poorti/shipments/{shipmentId}/pack`

### Path Parameters:
| Parameter | Example | Description |
|-----------|---------|-------------|
| `shipmentId` | `M100363` | ID of the shipment to pack |

### Authorization:
- Header: `Authorization: Bearer {TOKEN}`

### Request Body (JSON):
```json
{
  "facilityId": "MAPLEWOOD",
  "orderId": "171",
  "shipmentId": "M100363",
  "rejectedOrderItems": [],
  "shipmentPackageContents": []
}
```

### Response:
```json
{
  "packedShipmentId": "M100363",
  "status": "SUCCESS"
}
```

---

## 9. Ship Shipment
**Request Name:** Mark Shipment as Shipped  
**Method:** `POST`  
**Base URL:** `https://nextgen-maarg.hotwax.io`  
**Endpoint:** `/rest/s1/poorti/shipments/{shipmentId}/ship`

### Path Parameters:
| Parameter | Example | Description |
|-----------|---------|-------------|
| `shipmentId` | `M100363` | ID of the shipment to ship |

### Authorization:
- Header: `Authorization: Bearer {TOKEN}`

### Request Body (JSON):
```json
{
  "shipmentId": "M100363"
}
```

### Response:
```json
{
  "status": "SUCCESS",
  "shipmentId": "M100363"
}
```

---

## Authorization & Headers Reference

All endpoints except **#3 (Print Picklist)** require the following header:

```
Authorization: Bearer {YOUR_TOKEN}
```

**How to obtain token:**
1. Open browser DevTools (F12 or Right-click → Inspect)
2. Go to Network tab
3. Perform any action on the website
4. Look for request headers
5. Copy the Bearer token from the Authorization header

---

## Notes:
- Replace placeholder values (e.g., `M100363`, `MAPLEWOOD`) with actual data
- Query parameters should be URL-encoded if they contain special characters
- All timestamps follow ISO 8601 format
- Refer to individual endpoint responses for additional fields