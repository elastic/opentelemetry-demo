// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import type { NextApiRequest, NextApiResponse } from 'next';
import InstrumentationMiddleware from '../../utils/telemetry/InstrumentationMiddleware';
import AdGateway from '../../gateways/rpc/Ad.gateway';
import { Ad, Empty } from '../../protos/demo';

type TResponse = Ad[] | Empty | { error: string };

const handler = async ({ method, query }: NextApiRequest, res: NextApiResponse<TResponse>) => {
  switch (method) {
    case 'GET': {
      try {
        const { contextKeys = [] } = query;
        const { ads: adList } = await AdGateway.listAds(Array.isArray(contextKeys) ? contextKeys : contextKeys.split(','));

        return res.status(200).json(adList);
      } catch (error) {
        console.error('Failed to get ads:', error);
        return res.status(500).json({ error: 'Failed to retrieve ads' });
      }
    }

    default: {
      return res.status(405).send('');
    }
  }
};

export default InstrumentationMiddleware(handler);
