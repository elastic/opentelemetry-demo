# RCA KubeCon Demo Scripts

Docs for running scripts in this folder. 


## setup

The fast way to set things up is with the `setup` script. Before running it, be sure to copy 
[the .env.example file](./.env.example) and add all of the required values. Each script file SHOULD
source this .env file for you, but if it doesn't, run `$ source scripts/rca-demo/.env` to make sure.

Run the setup script from the repo root:

```
./scripts/rca-demo/setup
```

The output will guide you if you are missing anything required to make this work. You can check the
status of the pods by running `kubectl get pods`. 

Assuming everything is now running correctly, you should be able to visit the Astronomy Shop in
your browser at http://otel-demo.internal, and see signals in your configured ES/Kibana.

## trigger-demo scenario

The `trigger-demo-scenario` script will cause the cart service to fail to start properly. You can use this to test how the solution responds to the problem.

For the full scenario, set up a custom threshold rule like this:

![Custom threshold rule](threshold_rule.png "Custom threshold rule")

This rule will trigger when the demo scenario is activated and will be associated with the nginx ingress controller service. It can be used as a starting point to showcase the different exploration capabilities of the stack.

With `trigger-demo-scenario restore`, the system can be put back into a working state again.
