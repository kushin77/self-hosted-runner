import {
  APIResponse,
  ErrorCode,
  ErrorPayload,
  HttpStatus,
  successResponse,
  errorResponse,
  partialResponse,
  getHttpStatus,
} from '../../../src/lib/unified-response';

describe('Unified Response Schema', () => {
  const requestId = 'req_test_12345';

  describe('successResponse', () => {
    it('should create success response with data', () => {
      const data = { credentialId: 'cred_123', type: 'aws_sts' };
      const response = successResponse(data, requestId);

      expect(response.status).toBe('success');
      expect(response.data).toEqual(data);
      expect(response.error).toBeNull();
      expect(response.metadata.requestId).toBe(requestId);
      expect(response.metadata.version).toBe('v1');
    });

    it('should include ISO 8601 timestamp', () => {
      const response = successResponse({}, requestId);
      const timestamp = new Date(response.metadata.timestamp);
      
      expect(timestamp).toBeInstanceOf(Date);
      expect(timestamp.getTime()).toBeLessThanOrEqual(Date.now());
      expect(timestamp.getTime()).toBeGreaterThan(Date.now() - 1000);
    });

    it('should accept custom HTTP status code', () => {
      const response = successResponse({ id: 1 }, requestId, HttpStatus.CREATED);
      // Note: successResponse doesn't use status code directly, but it should be handled by caller
      expect(response.status).toBe('success');
    });
  });

  describe('errorResponse', () => {
    it('should create error response with required fields', () => {
      const response = errorResponse(
        ErrorCode.INVALID_TOKEN,
        'Token is invalid',
        requestId
      );

      expect(response.status).toBe('error');
      expect(response.data).toBeNull();
      expect(response.error).toBeDefined();
      expect(response.error!.code).toBe(ErrorCode.INVALID_TOKEN);
      expect(response.error!.message).toBe('Token is invalid');
    });

    it('should mark non-retryable errors by default', () => {
      const response = errorResponse(
        ErrorCode.PERMISSION_DENIED,
        'Access denied',
        requestId
      );

      expect(response.error!.retryable).toBe(false);
      expect(response.error!.retryAfter).toBeUndefined();
    });

    it('should support retryable errors with backoff', () => {
      const response = errorResponse(
        ErrorCode.RATE_LIMITED,
        'Rate limit exceeded',
        requestId,
        {
          retryable: true,
          retryAfter: 5000,
        }
      );

      expect(response.error!.retryable).toBe(true);
      expect(response.error!.retryAfter).toBe(5000);
    });

    it('should include additional details for debugging', () => {
      const details = { quota: 100, used: 100 };
      const response = errorResponse(
        ErrorCode.QUOTA_EXHAUSTED,
        'Quota exceeded',
        requestId,
        { retryable: true, details }
      );

      expect(response.error!.details).toEqual(details);
    });
  });

  describe('partialResponse', () => {
    it('should create partial response with warnings', () => {
      const data = [{ id: 1 }, { id: 2 }];
      const warnings = ['1 item excluded due to permission denied'];
      const response = partialResponse(data, warnings, requestId);

      expect(response.status).toBe('partial');
      expect(response.data).toEqual(data);
      expect(response.error).toBeNull();
      expect(response.metadata.warnings).toEqual(warnings);
    });

    it('should handle multiple warnings', () => {
      const response = partialResponse(
        {},
        ['Warning 1', 'Warning 2', 'Warning 3'],
        requestId
      );

      expect(response.metadata.warnings!.length).toBe(3);
    });
  });

  describe('getHttpStatus', () => {
    it('should map error codes to HTTP status codes', () => {
      expect(getHttpStatus(ErrorCode.INVALID_TOKEN)).toBe(HttpStatus.UNAUTHORIZED);
      expect(getHttpStatus(ErrorCode.NOT_FOUND)).toBe(HttpStatus.NOT_FOUND);
      expect(getHttpStatus(ErrorCode.RATE_LIMITED)).toBe(HttpStatus.TOO_MANY_REQUESTS);
      expect(getHttpStatus(ErrorCode.INTERNAL_ERROR)).toBe(HttpStatus.INTERNAL_SERVER_ERROR);
    });

    it('should return 500 for unknown error codes', () => {
      expect(getHttpStatus('unknown/error')).toBe(HttpStatus.INTERNAL_SERVER_ERROR);
    });
  });

  describe('Error Payload Structure', () => {
    it('should validate error code enum', () => {
      const validCodes = Object.values(ErrorCode);
      expect(validCodes).toContain(ErrorCode.INVALID_TOKEN);
      expect(validCodes).toContain(ErrorCode.RATE_LIMITED);
      expect(validCodes.length).toBeGreaterThan(10);
    });

    it('should support custom error codes (not just enum)', () => {
      const response = errorResponse(
        'custom/error-code',
        'Custom error',
        requestId
      );

      expect(response.error!.code).toBe('custom/error-code');
    });
  });

  describe('Response Metadata', () => {
    it('should always include metadata', () => {
      const successResp = successResponse({}, requestId);
      const errorResp = errorResponse(ErrorCode.INTERNAL_ERROR, 'Error', requestId);
      const partialResp = partialResponse({}, [], requestId);

      [successResp, errorResp, partialResp].forEach((resp) => {
        expect(resp.metadata).toBeDefined();
        expect(resp.metadata.requestId).toBe(requestId);
        expect(resp.metadata.timestamp).toBeDefined();
        expect(resp.metadata.version).toBe('v1');
      });
    });
  });
});
