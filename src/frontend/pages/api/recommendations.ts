// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import type { NextApiRequest, NextApiResponse } from 'next';
import InstrumentationMiddleware from '../../utils/telemetry/InstrumentationMiddleware';
import RecommendationsGateway from '../../gateways/rpc/Recommendations.gateway';
import { Empty, Product } from '../../protos/demo';
import ProductCatalogService from '../../services/ProductCatalog.service';

type TResponse = Product[] | Empty | { error: string };

const handler = async ({ method, query }: NextApiRequest, res: NextApiResponse<TResponse>) => {
  switch (method) {
    case 'GET': {
      try {
        const { productIds = [], sessionId = '', currencyCode = '' } = query;
        const { productIds: productList } = await RecommendationsGateway.listRecommendations(
          sessionId as string,
          productIds as string[]
        );
        const recommendedProductList = await Promise.all(
          productList.slice(0, 4).map(id => ProductCatalogService.getProduct(id, currencyCode as string))
        );

        return res.status(200).json(recommendedProductList);
      } catch (error) {
        console.error('Failed to get recommendations:', error);
        return res.status(500).json({ error: 'Failed to retrieve recommendations' });
      }
    }

    default: {
      return res.status(405).send('');
    }
  }
};

export default InstrumentationMiddleware(handler);
