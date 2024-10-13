import type { SyntheticsConfig } from "@elastic/synthetics";

export default (env) => {
  const config: SyntheticsConfig = {
    params: {
      url: "http://otel-demo.internal",
    },
    playwrightOptions: {
      ignoreHTTPSErrors: false,
    },
    /**
     * Configure global monitor settings
     */
    monitor: {
      schedule: 1,
      locations: [],
      privateLocations: [process.env.SYNTHETICS_PRIVATE_LOCATION],
    },
    /**
     * Project monitors settings
     */
    project: {
      id: "otel-demo-monitors",
      url: process.env.KIBANA_URL,
      space: "default",
    },
  };
  if (env !== "development") {
    /**
     * Override configuration specific to environment
     * Ex: config.params.url = ""
     */
  }
  return config;
};
