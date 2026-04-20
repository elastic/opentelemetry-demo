// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import { Component, ErrorInfo, ReactNode } from 'react';
import { trace } from '@opentelemetry/api';

interface IProps {
  children: ReactNode;
}

interface IState {
  hasError: boolean;
}

class ErrorBoundary extends Component<IProps, IState> {
  constructor(props: IProps) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(): IState {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('ErrorBoundary caught an error:', error, info);
    trace.getActiveSpan()?.recordException(error);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: '2rem', textAlign: 'center' }}>
          <h2>Something went wrong.</h2>
          <p>Please refresh the page and try again.</p>
        </div>
      );
    }

    return this.props.children;
  }
}

export default ErrorBoundary;
