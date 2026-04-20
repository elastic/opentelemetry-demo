// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import type { NextApiHandler } from 'next';
import CartGateway from '../../gateways/rpc/Cart.gateway';
import { AddItemRequest, Empty } from '../../protos/demo';
import ProductCatalogService from '../../services/ProductCatalog.service';
import { IProductCart, IProductCartItem } from '../../types/Cart';
import InstrumentationMiddleware from '../../utils/telemetry/InstrumentationMiddleware';

type TResponse = IProductCart | Empty;

const handler: NextApiHandler<TResponse> = async ({ method, body, query }, res) => {
  switch (method) {
    case 'GET': {
      try {
        const { sessionId = '', currencyCode = '' } = query;
        const { userId, items } = await CartGateway.getCart(sessionId as string);

        const productList: IProductCartItem[] = await Promise.all(
          items.map(async ({ productId, quantity }) => {
            const product = await ProductCatalogService.getProduct(productId, currencyCode as string);

            return {
              productId,
              quantity,
              product,
            };
          })
        );

        return res.status(200).json({ userId, items: productList });
      } catch (error) {
        console.error('Failed to get cart:', error);
        return res.status(500).json({ error: 'Failed to retrieve cart' } as unknown as TResponse);
      }
    }

    case 'POST': {
      try {
        const { userId, item } = body as AddItemRequest;

        await CartGateway.addItem(userId, item!);
        const cart = await CartGateway.getCart(userId);

        return res.status(200).json(cart);
      } catch (error) {
        console.error('Failed to add item to cart:', error);
        return res.status(500).json({ error: 'Failed to add item to cart' } as unknown as TResponse);
      }
    }

    case 'DELETE': {
      try {
        const { userId } = body as AddItemRequest;
        await CartGateway.emptyCart(userId);

        return res.status(204).send('');
      } catch (error) {
        console.error('Failed to empty cart:', error);
        return res.status(500).json({ error: 'Failed to empty cart' } as unknown as TResponse);
      }
    }

    default: {
      return res.status(405);
    }
  }
};

export default InstrumentationMiddleware(handler);
