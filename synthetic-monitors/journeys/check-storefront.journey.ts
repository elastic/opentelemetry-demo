import { journey, step, monitor, expect } from "@elastic/synthetics";

journey("Check storefront homepage", ({ page, params }) => {
  monitor.use({
    schedule: 10,
    id: "check-storefront-homepage",
  });
  step("launch application", async () => {
    await page.goto(params.url);
  });

  step("find slogan text", async () => {
    const header = await page.locator(
      "text=The best telescopes to see the world closer"
    );
    expect(header);
  });
});
