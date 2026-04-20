// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import { NextPageContext } from 'next';
import { trace } from '@opentelemetry/api';

interface IProps {
  statusCode?: number;
}

const ErrorPage = ({ statusCode }: IProps) => {
  return (
    <div style={{ padding: '2rem', textAlign: 'center' }}>
      <h1>{statusCode ? `${statusCode} – An error occurred` : 'An error occurred'}</h1>
      <p>
        {statusCode === 404
          ? 'The page you are looking for could not be found.'
          : 'Sorry, something went wrong on our end. Please try again later.'}
      </p>
    </div>
  );
};

ErrorPage.getInitialProps = ({ res, err }: NextPageContext) => {
  const statusCode = res ? res.statusCode : err ? (err as any).statusCode : 404;

  if (err) {
    trace.getActiveSpan()?.recordException(err);
  }

  return { statusCode };
};

export default ErrorPage;
