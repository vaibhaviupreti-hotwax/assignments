# Shopify Admin Extension — What I Did

## Objective

To build a small custom component that sits inside Shopify's admin panel and can actually update data (not just show it). This is a first test before connecting it to our Moqui backend (HotWax).

---

## 1. Getting set up

Created a free Shopify Partner account,
Created a development store. This store is just for testing — not a real shop.

Check tools:
- Node.js 22.12 or higher. I had an older version, so I used `nvm` to install and switch to Node 22.
- Git was already fine.
- Then I installed the Shopify CLI (the command-line tool Shopify gives you to build apps and extensions):
  ```
  npm install -g @shopify/cli@latest
  ```

---

## 2. Creating the app

I ran:
```
shopify app init
```

It asked me to log in, then asked what kind of project I wanted. I picked **"Build an extension-only app"** — because I don't need Shopify's own backend, since our actual backend will be Moqui.

This created a folder called `demo-app`.

---

## 3. Creating the extension

Inside that folder, I ran:
```
shopify app generate extension
```

It asked what type of extension I wanted. I picked **Admin action** (this is the type that shows up as a button inside a product page's "More actions" menu). I named it `quick-mutation-demo`.

---

## 4. Some annoying errors I had to fix

When I tried to run the app, I kept getting errors about the "locale" files (these are just text files that hold the wording shown in the extension, like a translations file).

The problems were:
- The JSON inside the files was broken/corrupted (some extra text had gotten mixed in by mistake)
- Shopify also needs a `"name"` field inside the default language file (English) — I had missed adding that
- One file was missing a closing bracket at the end

Once I cleaned up both files properly, the errors went away. Here's what they look like now:

**English file:**
```json
{
  "name": "Quick Mutation Demo",
  "welcome": "Welcome to the {{target}} extension!"
}
```

**French file:**
```json
{
  "name": "Quick Mutation Demo",
  "welcome": "Bienvenue dans l'extension {{target}} !"
}
```

---

## 5. Writing the actual feature

This is the main file: `extensions/quick-mutation-demo/src/ActionExtension.jsx`

**First version:** When you open the extension, it fetches the product's current title and shows it. There's a button that, when clicked, adds the word "(Updated)" to the end of the title and saves it back to Shopify.

**Improved version:** Instead of just adding a fixed word, I added a text box where I can type in any new title I want. When I click "Update Title," it saves whatever I typed — not a fixed value anymore.

To make this work, the extension talks directly to Shopify's Admin GraphQL API (this is just Shopify's way of letting you read and write data) using a `fetch` call from inside the extension code.

---

## 6. Testing it

I ran:
```
shopify app dev
```

This starts a live preview connected to my dev store.

Then I:
1. Opened the dev store's admin panel
2. Clicked into a specific product (not the product list — the extension only shows up once you're on one product's page)
3. Opened the "More actions" menu
4. Clicked on "Quick Mutation Demo"
5. A small window popped up showing the current title in an editable box
6. I typed a new title and clicked "Update Title"

It worked — the product's title actually changed in Shopify, and it stayed changed even after I closed the window and checked the products list again.

---

## 7. Saving my work to GitHub

Before committing, I checked the `.gitignore` file (this tells Git which files to skip, like passwords or temporary files). It already had the important stuff — `node_modules`, `.env`, and some database files. I just added a couple of lines to also ignore log files.

Then I committed and pushed everything:
```
git add .
git commit -m "Add quick mutation demo extension with editable product title"
```

Repo link: https://github.com/vaibhaviupreti-hotwax/assignments/tree/main/shopify-integration/demo-app

---

## Outcome(s)

A working extension that:
- Shows up inside Shopify's admin, on a product page
- Reads the product's real data
- Lets me type in a new title and actually save it back to Shopify — a real, working update, not just a UI mockup
