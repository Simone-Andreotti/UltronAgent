const { defineConfig } = require("@playwright/test");

module.exports = defineConfig({
  use: { baseURL: "http://127.0.0.1:4317" },
  webServer: {
    command: "node server.js",
    url: "http://127.0.0.1:4317",
    reuseExistingServer: true
  },
  workers: 1
});
