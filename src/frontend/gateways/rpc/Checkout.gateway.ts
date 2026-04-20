// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import { ChannelCredentials } from '@grpc/grpc-js';
import { CheckoutServiceClient, PlaceOrderRequest, PlaceOrderResponse } from '../../protos/demo';

const { CHECKOUT_ADDR = '' } = process.env;

const client = new CheckoutServiceClient(CHECKOUT_ADDR, ChannelCredentials.createInsecure());

const CheckoutGateway = () => ({
  placeOrder(order: PlaceOrderRequest) {
    return new Promise<PlaceOrderResponse>((resolve, reject) =>
      client.placeOrder(order, (error, response) => {
        if (error) {
          const enriched = new Error(`CheckoutService.placeOrder failed [gRPC ${error.code}]: ${error.details || error.message}`);
          (enriched as any).grpcCode = error.code;
          return reject(enriched);
        }
        resolve(response);
      })
    );
  },
});

export default CheckoutGateway();
