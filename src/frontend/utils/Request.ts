// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

interface IRequestParams {
  url: string;
  body?: object;
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE';
  queryParams?: Record<string, any>;
  headers?: Record<string, string>;
}

const request = async <T>({
  url = '',
  method = 'GET',
  body,
  queryParams = {},
  headers = {
    'content-type': 'application/json',
  },
}: IRequestParams): Promise<T> => {
  const flatParams: Record<string, string> = {};
  for (const [key, value] of Object.entries(queryParams)) {
    if (Array.isArray(value)) {
      value.forEach((v, i) => {
        flatParams[`${key}[${i}]`] = String(v);
      });
    } else if (value !== undefined && value !== null) {
      flatParams[key] = String(value);
    }
  }

  const response = await fetch(`${url}?${new URLSearchParams(flatParams).toString()}`, {
    method,
    body: body ? JSON.stringify(body) : undefined,
    headers,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`HTTP ${response.status} ${response.statusText}: ${text}`);
  }

  const responseText = await response.text();

  if (!responseText) return undefined as unknown as T;

  try {
    return JSON.parse(responseText) as T;
  } catch {
    throw new Error(`Failed to parse response as JSON: ${responseText}`);
  }
};

export default request;
