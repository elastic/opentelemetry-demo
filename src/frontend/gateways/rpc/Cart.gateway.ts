// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import { ChannelCredentials } from '@grpc/grpc-js';
import { Cart, CartItem, CartServiceClient, Empty } from '../../protos/demo';

const { CART_ADDR = '' } = process.env;

const client = new CartServiceClient(CART_ADDR, ChannelCredentials.createInsecure());

const CartGateway = () => ({
  getCart(userId: string) {
    return new Promise<Cart>((resolve, reject) =>
      client.getCart({ userId }, (error, response) => {
        if (error) {
          const enriched = new Error(`CartService.getCart failed [gRPC ${error.code}]: ${error.details || error.message}`);
          (enriched as any).grpcCode = error.code;
          return reject(enriched);
        }
        resolve(response);
      })
    );
  },
  addItem(userId: string, item: CartItem) {
    return new Promise<Empty>((resolve, reject) =>
      client.addItem({ userId, item }, (error, response) => {
        if (error) {
          const enriched = new Error(`CartService.addItem failed [gRPC ${error.code}]: ${error.details || error.message}`);
          (enriched as any).grpcCode = error.code;
          return reject(enriched);
        }
        resolve(response);
      })
    );
  },
  emptyCart(userId: string) {
    return new Promise<Empty>((resolve, reject) =>
      client.emptyCart({ userId }, (error, response) => {
        if (error) {
          const enriched = new Error(`CartService.emptyCart failed [gRPC ${error.code}]: ${error.details || error.message}`);
          (enriched as any).grpcCode = error.code;
          return reject(enriched);
        }
        resolve(response);
      })
    );
  },
});

export default CartGateway();
