export interface ApiErrorDetail {
  field?: string;
  code: string;
  message: string;
}

export interface ApiMeta {
  page?: number;
  limit?: number;
  total?: number;
  correlationId?: string;
}

export interface ApiResponse<T> {
  success: boolean;
  message?: string;
  data?: T;
  errors?: ApiErrorDetail[];
  meta?: ApiMeta;
}

export interface PaginationQuery {
  page?: number;
  limit?: number;
  sort?: string;
}

export function ok<T>(data: T, meta?: ApiMeta, message = "OK"): ApiResponse<T> {
  return { success: true, message, data, meta };
}

export function fail(message: string, errors: ApiErrorDetail[] = [], meta?: ApiMeta): ApiResponse<never> {
  return { success: false, message, errors, meta };
}
