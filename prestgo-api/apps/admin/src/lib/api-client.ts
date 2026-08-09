export interface ApiClientOptions {
  baseUrl?: string;
  accessToken?: string;
}

export interface ApiResponse<T> {
  success: boolean;
  message?: string;
  data?: T;
  errors?: Array<{ code: string; message: string }>;
}

export class ApiClient {
  private readonly baseUrl: string;
  private accessToken?: string;

  constructor(options: ApiClientOptions = {}) {
    this.baseUrl = options.baseUrl ?? "/api/v1";
    this.accessToken = options.accessToken;
  }

  setAccessToken(token: string): void {
    this.accessToken = token;
  }

  clearAccessToken(): void {
    this.accessToken = undefined;
  }

  async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const headers = new Headers(init.headers);
    headers.set("accept", "application/json");
    headers.set("content-type", "application/json");

    if (this.accessToken) {
      headers.set("authorization", `Bearer ${this.accessToken}`);
    }

    const response = await fetch(`${this.baseUrl}${path}`, { ...init, headers });

    const data = (await response.json()) as ApiResponse<T>;

    if (!response.ok || !data.success) {
      throw new Error(data.message ?? `API request failed with status ${response.status}`);
    }

    return data.data as T;
  }

  async get<T>(path: string): Promise<T> {
    return this.request<T>(path, { method: "GET" });
  }

  async post<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>(path, {
      method: "POST",
      body: JSON.stringify(body)
    });
  }

  async patch<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>(path, {
      method: "PATCH",
      body: JSON.stringify(body)
    });
  }

  async put<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>(path, {
      method: "PUT",
      body: JSON.stringify(body)
    });
  }

  async delete<T>(path: string): Promise<T> {
    return this.request<T>(path, { method: "DELETE" });
  }

  /**
   * Envoie un vrai fichier (multipart/form-data).
   *
   * On n'utilise PAS `request()` ici : celle-ci force l'en-tête
   * `content-type: application/json`. Pour un envoi multipart, il faut au
   * contraire laisser le navigateur écrire lui-même le content-type, car il
   * doit y ajouter une « frontière » (boundary) qu'il est seul à connaître.
   */
  async upload<T>(path: string, file: File, fields: Record<string, string> = {}): Promise<T> {
    const form = new FormData();
    form.append("file", file);
    for (const [key, value] of Object.entries(fields)) {
      form.append(key, value);
    }

    const headers = new Headers();
    headers.set("accept", "application/json");
    if (this.accessToken) {
      headers.set("authorization", `Bearer ${this.accessToken}`);
    }

    const response = await fetch(`${this.baseUrl}${path}`, { method: "POST", body: form, headers });
    const data = (await response.json()) as ApiResponse<T>;

    if (!response.ok || !data.success) {
      throw new Error(data.message ?? `Échec de l'envoi (statut ${response.status})`);
    }

    return data.data as T;
  }

  /**
   * Récupère le contenu binaire d'un fichier protégé.
   *
   * On ne peut pas simplement mettre l'URL dans un `<a href>` ou un `<img src>` :
   * le navigateur n'y ajouterait pas le token d'authentification. On télécharge
   * donc le contenu avec fetch, puis on en fait une URL temporaire locale.
   * L'appelant doit libérer cette URL avec `URL.revokeObjectURL` quand il a fini.
   */
  async fetchBlobUrl(path: string): Promise<string> {
    const headers = new Headers();
    if (this.accessToken) {
      headers.set("authorization", `Bearer ${this.accessToken}`);
    }

    const response = await fetch(`${this.baseUrl}${path}`, { headers });
    if (!response.ok) {
      throw new Error(`Fichier inaccessible (statut ${response.status})`);
    }

    return URL.createObjectURL(await response.blob());
  }
}

export const apiClient = new ApiClient();
