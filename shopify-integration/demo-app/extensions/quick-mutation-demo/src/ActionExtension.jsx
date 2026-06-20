import "@shopify/ui-extensions/preact";
import {render} from 'preact';
import {useEffect, useState} from 'preact/hooks';

export default async () => {
  render(<Extension />, document.body);
}

function Extension() {
  const {i18n, close, data, extension: {target}} = shopify;
  const [productTitle, setProductTitle] = useState('');
  const [newTitle, setNewTitle] = useState('');
  const [saving, setSaving] = useState(false);

  // QUERY: fetch current product title
  useEffect(() => {
    (async function getProductInfo() {
      const getProductQuery = {
        query: `query Product($id: ID!) {
          product(id: $id) {
            title
          }
        }`,
        variables: {id: data.selected[0].id},
      };

      const res = await fetch("shopify:admin/api/graphql.json", {
        method: "POST",
        body: JSON.stringify(getProductQuery),
      });

      const productData = await res.json();
      setProductTitle(productData.data.product.title);
      setNewTitle(productData.data.product.title);
    })();
  }, [data.selected]);

  // MUTATION: update product title with user input
  async function handleUpdateTitle() {
    setSaving(true);
    try {
      const updateProductMutation = {
        query: `mutation UpdateProduct($input: ProductInput!) {
          productUpdate(input: $input) {
            product {
              id
              title
            }
            userErrors {
              field
              message
            }
          }
        }`,
        variables: {
          input: {
            id: data.selected[0].id,
            title: newTitle,
          },
        },
      };

      const res = await fetch("shopify:admin/api/graphql.json", {
        method: "POST",
        body: JSON.stringify(updateProductMutation),
      });

      const result = await res.json();

      if (result.data?.productUpdate?.userErrors?.length) {
        console.error(result.data.productUpdate.userErrors);
      } else {
        setProductTitle(result.data.productUpdate.product.title);
      }
    } catch (err) {
      console.error('Mutation failed', err);
    } finally {
      setSaving(false);
    }
  }

  return (
    <s-admin-action>
      <s-stack direction="block" gap="base">
        <s-text type="strong">{i18n.translate('welcome', {target})}</s-text>
        <s-text>Current product: {productTitle}</s-text>
        <s-text-field
          label="New title"
          value={newTitle}
          onChange={(e) => {
            const target = /** @type {any} */ (e.target);
            setNewTitle(target.value);
          }}
        />
      </s-stack>
      <s-button slot="primary-action" onClick={handleUpdateTitle} disabled={saving}>
        {saving ? 'Updating...' : 'Update Title'}
      </s-button>
      <s-button slot="secondary-actions" onClick={() => {
          close();
      }}>Close</s-button>
    </s-admin-action>
  );
}