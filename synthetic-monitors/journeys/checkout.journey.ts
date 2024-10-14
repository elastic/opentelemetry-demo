import { journey, step, monitor } from "@elastic/synthetics";

journey("Checkout two items", async ({ page, params, context }) => {
  monitor.use({
    schedule: 3,
  });

  step("Go to store home", async () => {
    await page.goto(params.url);
  });

  step("Add first item to cart", async () => {
    await page.getByRole("button", { name: "Go Shopping" }).click();
    await page
      .getByRole("link", {
        name: "National Park Foundation Explorascope $ 101.96",
      })
      .click();
    await page.getByRole("button", { name: "cart Add To Cart" }).click();
  });

  step("Add two of second item to cart", async () => {
    await page.getByRole("navigation").getByRole("link").click();
    await page.getByRole("button", { name: "Go Shopping" }).click();
    await page.getByRole("link", { name: "Roof Binoculars $ 209.95" }).click();
    await page.getByRole("main").getByRole("combobox").selectOption("2");
    await page.getByRole("button", { name: "cart Add To Cart" }).click();
  });

  step("Checkout", async () => {
    await page.reload(); // Sometimes the cart page needs a reload to recognize the items
    await page.getByRole("button", { name: "Place Order" }).click();
  });

  step("Verify checkout", async () => {
    await page.waitForSelector("text=We've sent you a confirmation email");
  });
});
