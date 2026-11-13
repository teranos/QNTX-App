# push

The token Apple gives a phone, for the node to reach it by.

The node tells the phone what is about to be said to an agent, fifteen minutes
before it is (teranos/QNTX `server/phones.go`). For that it needs the phone's
token, which only the app on the phone can ask Apple for.

## What the page does

```ts
const { token, platform } = await invoke('plugin:push|token');
```

The first call asks the person whether QNTX may send notifications. Allowed,
it answers the token in hex and `ios`. The page hands both to the node at
`POST /api/phones`, in the person's own session: the node takes a phone from
nobody else.

Refused in words when notifications are turned off for QNTX in Settings, when
Apple gives no token, and off iOS, where there is none.

## What it needs

- Push Notifications on the App ID, and a provisioning profile made after.
- `aps-environment` in the app's entitlements, which
  `.github/scripts/ios-project.py` writes into the generated project.

## What it does not do

It does not hear a tap. A notification tapped opens the app, and the page asks
the node what waits.

It has not been run on a phone by whoever wrote it: it compiles in CI for the
simulator, which Apple gives no token.
