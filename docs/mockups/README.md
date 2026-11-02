# Demo images

Source for the images in [`../screenshots`](../screenshots).

- **Tablet screens (01–13)** are the resource's real UI from [`html/`](../../html), rendered in Chromium with
  `tablet-mock.js` standing in for the server, over an in-game office backdrop (`bg-office.jpg`).
- **14–16** (job-offer pop-up, driving HUD) are ox_lib-style mockups from `scenes.js` + `render.js` + `index.html`.
- `sheet.html` builds the `00-overview.jpg` contact sheet.

```bash
npm i -D playwright && npx playwright install chromium
node shoot.js
```

Preview the tablet in a browser without FiveM: serve the repo root and open
`html/index.html?app=finance` with `tablet-mock.js` injected before `app.js`
(that's what `shoot.js` does with `page.addInitScript`).
