import { journey, step, monitor, expect } from '@elastic/synthetics';

journey('Check storefront homepage', ({ page, params }) => {
  // Only relevant for the push command to create
  // monitors in Kibana
  monitor.use({
    id: 'example-monitor',
    schedule: 10,
  });
  step('launch application', async () => {
    await page.goto('http://otel-demo.internal');
  });

  step('find slogan text', async () => {
    const header = await page.locator('text=The best telescopes to see the world closer');
    expect(header);
  });
});
