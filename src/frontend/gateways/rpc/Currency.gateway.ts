// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import { ChannelCredentials } from '@grpc/grpc-js';
import { GetSupportedCurrenciesResponse, CurrencyServiceClient, Money } from '../../protos/demo';

const { CURRENCY_ADDR = '' } = process.env;

const client = new CurrencyServiceClient(CURRENCY_ADDR, ChannelCredentials.createInsecure());

const CurrencyGateway = () => ({
  convert(from: Money, toCode: string) {
    return new Promise<Money>((resolve, reject) =>
      client.convert({ from, toCode }, (error, response) => {
        if (error) {
          const enriched = new Error(`CurrencyService.convert failed [gRPC ${error.code}]: ${error.details || error.message}`);
          (enriched as any).grpcCode = error.code;
          return reject(enriched);
        }
        resolve(response);
      })
    );
  },
  getSupportedCurrencies() {
    return new Promise<GetSupportedCurrenciesResponse>((resolve, reject) =>
      client.getSupportedCurrencies({}, (error, response) => {
        if (error) {
          const enriched = new Error(`CurrencyService.getSupportedCurrencies failed [gRPC ${error.code}]: ${error.details || error.message}`);
          (enriched as any).grpcCode = error.code;
          return reject(enriched);
        }
        resolve(response);
      })
    );
  },
});

export default CurrencyGateway();
