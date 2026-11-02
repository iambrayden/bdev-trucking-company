# UI mockups

Source for the images in [`../screenshots`](../screenshots). They are **mockups** of the in-game UI,
styled after ox_lib's context menus, dialogs, notifications, text UI and progress circle, plus ox_target.
The text and numbers in them match the real strings and default config of this resource.

- `scenes.js`: one entry per image (menu options, dialogs, notifications, caption)
- `render.js` / `index.html`: draws the background and the ox_lib-style components
- `sheet.html`: the overview contact sheet
- `shoot.js`: renders everything with Playwright

```bash
npm i -D playwright && npx playwright install chromium
node shoot.js
```

Open `index.html?s=03-management` in a browser to preview a single scene.
