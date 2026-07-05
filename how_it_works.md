oydlp

# Why Not Cafe — How The System Works

This document explains the whole system in plain English.
No technical words. Just what it does and how everything connects.

---

## The Big Picture

The system has two parts.

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   PART 1: The Menu Website         PART 2: The Admin Panel  │
│                                                             │
│   What customers see               What you and your        │
│   when they scan the QR code       team see when you        │
│   or open the link.                log in to manage         │
│                                    the menu.                │
│                                                             │
│   Anyone can open it.              Only approved people     │
│   No login needed.                 can log in.              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Both parts live on the same website link.

The menu is at:   **yourcafe.web.app**
The admin is at:  **yourcafe.web.app/admin**

---

## Where The Data Lives

All your menu data lives in **the cloud** — Google's servers.
You do not need your own server or computer to be on all the time.

```
                    ┌─────────────────────────────┐
                    │                             │
                    │        THE CLOUD            │
                    │     (Google Firebase)       │
                    │                             │
                    │  ┌────────────────────────┐ │
                    │  │  Live Menu             │ │
                    │  │  (what customers see)  │ │
                    │  └────────────────────────┘ │
                    │                             │
                    │  ┌────────────────────────┐ │
                    │  │  Draft Menu            │ │
                    │  │  (your work in progress│ │
                    │  │   not live yet)        │ │
                    │  └────────────────────────┘ │
                    │                             │
                    │  ┌────────────────────────┐ │
                    │  │  Cafe Info             │ │
                    │  │  (name, logo, phone,   │ │
                    │  │   opening hours, etc.) │ │
                    │  └────────────────────────┘ │
                    │                             │
                    │  ┌────────────────────────┐ │
                    │  │  Menu Photos           │ │
                    │  │  (all item images)     │ │
                    │  └────────────────────────┘ │
                    │                             │
                    └─────────────────────────────┘
```

This is all **completely free** as long as you stay within Google's free limits.

---

## How A Customer Uses The Menu

```
  Customer at your cafe
         │
         │  scans QR code on the table
         │  (or opens link from Instagram / WhatsApp)
         ▼
  ┌──────────────────────────────────────────┐
  │          MENU WEBSITE OPENS              │
  │                                          │
  │  Shows:                                  │
  │  • Your cafe logo and name               │
  │  • All sections (Coffee, Food, Shakes…)  │
  │  • All items with photo, price, details  │
  │                                          │
  └──────────────────────────────────────────┘
         │
         │  Customer can:
         │
         ├──▶  Search by name  (type "cold")
         │         └── shows all items with "cold" in the name
         │
         ├──▶  Search by ingredient  (type "chocolate")
         │         └── shows all items that have chocolate
         │
         ├──▶  Tap a section chip  (e.g. "Coffee")
         │         └── filters to only coffee items
         │
         └──▶  See item status:
                   ├── ✅  Available now
                   ├── 🕐  Available after 5 PM
                   └── ❌  Not available today
```

No login. No account. Just open and browse.

---

## How You Manage The Menu (Admin Flow)

```
  You (owner / manager / staff)
         │
         │  go to:  yourcafe.web.app/admin
         ▼
  ┌─────────────────────────────┐
  │   SIGN IN WITH GOOGLE       │
  │                             │
  │   Click "Sign in"           │
  │   Pick your Google account  │
  └─────────────────────────────┘
         │
         │  System checks:
         │  "Is this person approved to manage the cafe?"
         │
         ├── If YES ──▶  Admin Panel opens
         │
         └── If NO  ──▶  "Access Denied" screen
                          You are immediately signed out.
                          (Random people who guess the URL cannot get in.)
```

---

## Inside The Admin Panel

```
  ┌─────────────────────────────────────────────────────────────┐
  │                       ADMIN PANEL                           │
  │                                                             │
  │  ┌───────────┐  ┌──────────┐  ┌───────┐  ┌─────────────┐  │
  │  │ Dashboard │  │ Sections │  │ Items │  │   Settings  │  │
  │  └───────────┘  └──────────┘  └───────┘  └─────────────┘  │
  │                                                             │
  │  Dashboard:   See total items, sections, last update time   │
  │                                                             │
  │  Sections:    Add / rename / hide / reorder sections        │
  │               (Coffee, Food, Beverages, Specials…)          │
  │                                                             │
  │  Items:       Add / edit / delete items                     │
  │               Upload photo, set price, mark veg/non-veg     │
  │               Set available time, toggle available/not      │
  │                                                             │
  │  Settings:    Change cafe name, logo, phone, hours          │
  │                                                             │
  │                                                             │
  │  ┌─────────────────────────────────────────────────────┐   │
  │  │  ● Unsaved changes — Publish to go live             │   │
  │  └─────────────────────────────────────────────────────┘   │
  │                                                             │
  └─────────────────────────────────────────────────────────────┘
```

The orange banner at the bottom appears whenever you have made changes
that customers have not seen yet.

---

## The Draft → Publish System

This is the most important thing to understand.

**Changes do NOT go live immediately.**

```
  You edit an item price
  (e.g. Cold Coffee: ₹120 → ₹130)
         │
         ▼
  ┌─────────────────────────┐
  │  DRAFT                  │
  │  (saved in the cloud,   │
  │   only YOU can see it)  │
  │                         │
  │  Cold Coffee = ₹130 ✏️  │
  └─────────────────────────┘
         │
         │  Customers still see:
         │  Cold Coffee = ₹120  (the old price)
         │
         │  You keep editing more things if you want.
         │  Nothing goes live until you say so.
         │
         ▼
  You click  [ Publish Menu ]
         │
         ▼
  ┌─────────────────────────┐
  │  LIVE MENU              │
  │  (what customers see)   │
  │                         │
  │  Cold Coffee = ₹130 ✅  │
  └─────────────────────────┘
         │
         ▼
  New visitors → see the new price immediately.
  Existing visitors (page already open) → see it within 5 minutes.
```

**Why this is good:**
You can make 10 different changes (new items, price changes, hide a section)
and publish them all at once — customers never see half-done work.

---

## What Happens When You Publish

```
                    YOU
                     │
                     │  click  [ Publish Menu ]
                     ▼
           ┌─────────────────┐
           │   DRAFT MENU    │
           │   (your edits)  │
           └────────┬────────┘
                    │
                    │  System combines everything
                    │  into one clean package
                    ▼
           ┌─────────────────┐
           │   LIVE MENU     │
           │   (customers    │
           │    read this)   │
           └─────────────────┘
                    │
                    ▼
           New visitors see the update immediately.
           Existing visitors see it within 5 minutes.
```

The publish button is available to:

- Owner → always
- Manager → always
- Staff → cannot publish (staff can only toggle available/unavailable)

---

## Who Can Do What (Roles)

```
  ┌────────────────────────────────────────────────────────────┐
  │                                                            │
  │   OWNER (you)                                              │
  │   ─────────────────────────────────────────────────────   │
  │   ✅ Everything below                                      │
  │   ✅ Add or remove other admin accounts                    │
  │   ✅ Change someone's role                                 │
  │                                                            │
  ├────────────────────────────────────────────────────────────┤
  │                                                            │
  │   MANAGER  (e.g. your cafe manager)                        │
  │   ─────────────────────────────────────────────────────   │
  │   ✅ Add, edit, delete sections                            │
  │   ✅ Add, edit, delete items                               │
  │   ✅ Change prices                                         │
  │   ✅ Change availability and timings                       │
  │   ✅ Publish the menu                                      │
  │   ❌ Cannot manage admin accounts                          │
  │                                                            │
  ├────────────────────────────────────────────────────────────┤
  │                                                            │
  │   STAFF  (e.g. a counter person)                           │
  │   ─────────────────────────────────────────────────────   │
  │   ✅ Toggle items: Available / Not Available               │
  │   ❌ Cannot edit prices, names, sections                   │
  │   ❌ Cannot publish                                        │
  │                                                            │
  └────────────────────────────────────────────────────────────┘
```

If someone tries to access something they are not allowed to,
the button simply does not appear for them.

---

## How A Staff Member Updates Availability

The most common daily task. A staff member marks something as "sold out" or "back in stock".

```
  Staff opens admin panel on their phone
         │
         ▼
  Goes to Items page
         │
         ▼
  Finds "Veg Burger"
         │
         ▼
  Taps the toggle:  Available ──▶  Not Available
         │
         ▼
  That is saved immediately.
         │
         ▼
  Staff taps... wait, staff cannot publish.
         │
  So the manager or owner must publish for
  the change to appear on the customer menu.

  (You can decide: should staff be able to
   publish availability changes only?
   This can be adjusted later.)
```

---

## How Item Images Work

```
  You take a photo of "Cold Coffee"
  on your phone
         │
         ▼
  In the admin panel → edit item → upload photo
         │
         │  The app automatically shrinks the photo
         │  (so it loads fast for customers)
         │
         ▼
  Photo is saved in the cloud
         │
         ▼
  The item now has an image URL stored with it
         │
         ▼
  When you Publish → customers see the photo
```

If you delete an item, the photo is also deleted from the cloud automatically.
No storage waste.

---

## How The Menu Stays Updated For Customers

Customers do not need to refresh the page constantly.

```
  Customer opens the menu
         │
         ▼
  Menu loads immediately from the cloud
  (takes less than 1 second)
         │
         ▼
  Customer is browsing…
         │
         │  Every 5 minutes, quietly in the background:
         │  The app checks — "Did the menu change?"
         │
         ├── No change → customer keeps seeing the same menu (no disruption)
         │
         └── Menu changed → app quietly updates in the background
                            Customer sees new menu on next scroll
```

This means if you publish a change, customers who already have the page open
will see it within 5 minutes without doing anything.

---

## How A New Admin Is Added

You cannot sign up yourself. The owner must manually approve each person.

**First version (how it works right now):**

The owner adds new admins directly inside Google's Firebase website.
It takes about 2 minutes and requires no coding — just filling in a form.

```
  New person wants admin access
         │
         ▼
  They sign in with their Google account
  at  yourcafe.web.app/admin
         │
         ▼
  They see: "Access Denied"
  (expected — they are not approved yet)
         │
         ▼
  They tell the owner their Gmail address
         │
         ▼
  Owner goes to Google Firebase website
  → opens the database
  → adds the person's details manually
  → sets their role (manager or staff)
         │
         ▼
  The new person signs in again
  → now they have access
```

**Future update (coming after the initial launch):**

Once an "Admin Management" page is built into the admin panel,
the owner will be able to add people directly from the website
without going to any external page.

This means if someone leaves the cafe, the owner just sets their account to inactive.
They immediately lose access — no passwords to change.

---

## What It Costs

```
  Everything is FREE as long as:

  ┌───────────────────────────────────────────────────────────┐
  │                                                           │
  │  Visitors per day:   Fine for a typical cafe             │
  │  Menu items:         Up to 300-500 items comfortably     │
  │  Photo size:         Keep each photo under 150KB         │
  │  Admins:             3-4 people                          │
  │                                                           │
  │  No monthly fee.                                          │
  │  No credit card needed.                                   │
  │  Hosted on Google's servers for free.                     │
  │                                                           │
  └───────────────────────────────────────────────────────────┘
```

---

## Summary In One Diagram

```
                        GOOGLE CLOUD
                      ┌─────────────┐
                      │             │
       ┌──────────────│  Live Menu  │──────────────┐
       │  reads       │             │              │
       │              └──────┬──────┘              │
       ▼                     │ publish             │
  ┌──────────┐               │                    ▼
  │ CUSTOMER │          ┌────┴─────┐         ┌─────────┐
  │  MENU    │          │  DRAFT   │◀────────│  ADMIN  │
  │ WEBSITE  │          │   MENU   │  edits  │  PANEL  │
  └──────────┘          └──────────┘         └─────────┘
  Anyone can see.    Not public.          Login required.
  No login needed.   Only admins can      Google account
                     see and edit.        must be approved.
```

---

## Things To Know That Are Not Bugs

These are known limitations. They are not mistakes — they are tradeoffs chosen
to keep the system completely free.

**1. Changes take up to 5 minutes to appear for open browsers**
This is normal. Customers who just opened the page need to wait up to 5 minutes
to see any updates you published. New visitors see it immediately.

**2. Available/Unavailable times use the customer's phone clock**
If a customer's phone clock is wrong, they might see the wrong availability.
This is rare and not worth worrying about for a cafe.

**3. The menu cannot be found on Google Search**
Customers will only reach your menu through a QR code, Instagram, WhatsApp,
or a direct link. You cannot rank on Google with this setup.
That is fine since most cafe customers scan a QR code at the table anyway.

**4. Two people editing at exactly the same moment can overwrite each other**
If two admins edit different items at the exact same second, one might lose
their change. This almost never happens in practice with 2-3 admins.
The solution is simple: do not edit at the same time.
