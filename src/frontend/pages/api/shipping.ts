// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import type { NextApiRequest, NextApiResponse } from 'next';
import InstrumentationMiddleware from '../../utils/telemetry/InstrumentationMiddleware';
import ShippingGateway from '../../gateways/http/Shipping.gateway';
import { Address, CartItem, Empty, Money } from '../../protos/demo';
import CurrencyGateway from '../../gateways/rpc/Currency.gateway';

type TResponse = Money | Empty;

const handler = async ({ method, query }: NextApiRequest, res: NextApiResponse<TResponse>) => {
  switch (method) {
    case 'GET': {
      try {
        const { itemList = '', currencyCode = 'USD', address = '' } = query;
        const { costUsd } = await ShippingGateway.getShippingCost(JSON.parse(itemList as string) as CartItem[],
            JSON.parse(address as string) as Address);
        const cost = await CurrencyGateway.convert(costUsd!, currencyCode as string);

        return res.status(200).json(cost!);
      } catch (error) {
        console.error('Failed to get shipping cost:', error);
        return res.status(500).json({ error: 'Failed to retrieve shipping cost' } as unknown as TResponse);
      }
    }

    default: {
      return res.status(405);
    }
  }
};

export default InstrumentationMiddleware(handler);
