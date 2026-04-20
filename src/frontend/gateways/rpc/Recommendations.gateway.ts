// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import { ChannelCredentials } from '@grpc/grpc-js';
import { ListRecommendationsResponse, RecommendationServiceClient } from '../../protos/demo';

const { RECOMMENDATION_ADDR = '' } = process.env;

const client = new RecommendationServiceClient(RECOMMENDATION_ADDR, ChannelCredentials.createInsecure());

const RecommendationsGateway = () => ({
  listRecommendations(userId: string, productIds: string[]) {
    return new Promise<ListRecommendationsResponse>((resolve, reject) =>
      client.listRecommendations({ userId, productIds }, (error, response) => {
        if (error) {
          const enriched = new Error(`RecommendationService.listRecommendations failed [gRPC ${error.code}]: ${error.details || error.message}`);
          (enriched as any).grpcCode = error.code;
          return reject(enriched);
        }
        resolve(response);
      })
    );
  },
});

export default RecommendationsGateway();
