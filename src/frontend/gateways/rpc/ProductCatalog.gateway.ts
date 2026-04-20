// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import { ChannelCredentials } from '@grpc/grpc-js';
import { ListProductsResponse, Product, ProductCatalogServiceClient } from '../../protos/demo';

const { PRODUCT_CATALOG_ADDR = '' } = process.env;

const client = new ProductCatalogServiceClient(PRODUCT_CATALOG_ADDR, ChannelCredentials.createInsecure());

const ProductCatalogGateway = () => ({
  listProducts() {
    return new Promise<ListProductsResponse>((resolve, reject) =>
      client.listProducts({}, (error, response) => {
        if (error) {
          const enriched = new Error(`ProductCatalogService.listProducts failed [gRPC ${error.code}]: ${error.details || error.message}`);
          (enriched as any).grpcCode = error.code;
          return reject(enriched);
        }
        resolve(response);
      })
    );
  },
  getProduct(id: string) {
    return new Promise<Product>((resolve, reject) =>
      client.getProduct({ id }, (error, response) => {
        if (error) {
          const enriched = new Error(`ProductCatalogService.getProduct failed [gRPC ${error.code}]: ${error.details || error.message}`);
          (enriched as any).grpcCode = error.code;
          return reject(enriched);
        }
        resolve(response);
      })
    );
  },
});

export default ProductCatalogGateway();
