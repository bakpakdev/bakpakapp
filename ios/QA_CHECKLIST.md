# iOS Rewrite QA Checklist

## Authentication
- Register creates account and logs in.
- Login returns user and persists token.
- Logout clears token and returns to auth screens.

## Core shopping flow
- Home feed loads discover products.
- Search query and category filtering return results.
- Product detail opens and shows listing data.
- Message seller routes user to messages conversation.

## Listing flow
- Create listing form supports gender/category/size/dorm selection.
- Edit listing loads existing fields and saves updates.

## Messaging
- Conversations list loads.
- Conversation messages load.
- Sending a message updates thread.

## Profile and social
- Profile screen shows user data.
- My listings loads current user listings.
- Liked/Saved screens load social products.
- Edit profile saves data.

## Commerce
- Cart loads items.
- Checkout form present and ready for order integration.
- Orders list loads historical orders.

## Branding/UI parity
- UO green (`#154733`) used for primary accents.
- Tab structure matches Home/Search/Sell/Messages/Profile.
