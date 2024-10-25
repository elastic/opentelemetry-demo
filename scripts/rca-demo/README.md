# RCA KubeCon Demo Scripts

Docs for running scripts in this folder. It is highly recommended to run these scripts while you are in the root of the repo, e.g. `./scripts/rca-demo/{script_name}`

### Environment variables

Please be sure to check the latest docs in the `.env.example` file in this folder to explain the required env vars needed for these scripts to run.

Most of these scripts require env vars that should be set in a copy of `.env.example` that you've named `.env` and placed in this directory. You can create more .env.* files. By default, scripts will auto-source `.env` in this directory. To change which file gets auto-sourced, use:

```
ENV_FILE_PATH=./scripts/rca-demo/.env.{suffix} ./scripts/rca-demo/{script_name}
```

## setup

This will primarily set up **the k8s otel demo cluster**.

```
./scripts/rca-demo/setup
```

The output will guide you if you are missing anything required to make this work. You can check the status of the pods by running `kubectl get pods`. 

Assuming everything is now running correctly, you should be able to visit the Astronomy Shop in your browser at http://otel-demo.internal, and see signals in your configured ES/Kibana.

## post-setup

This script sets up assets in Kibana and Elasticsearch related to this demo, without needing to do the full kubernetes + helm install process. It will install alerting rules, data views, mapping updates, and advanced configuration settings required for the demo to work. Many of the definitions used for creating these assets can be found in the `scripts/rca-demo/data` directory.

```
./scripts/rca-demo/post-setup
```

Remember: you can create more .env.other files with different sets of values to run this script against a different ES/Kibana set up (e.g. keep .env for your local set up and .env.cloud for a cloud setup, etc.). To auto-source a different env file, run this like this:

```
ENV_FILE_PATH=./scripts/rca-demo/.env.cloud ./scripts/rca-demo/post-setup
```

## trigger-demo scenario

The `trigger-demo-scenario` script will cause the cart service to fail to start properly. You can use this to test how the solution responds to the problem.

Use `trigger-demo-scenario restore` to put the cart service back into a working state again.
