export type PrestgoEnvironment = "development" | "test" | "production";

export interface PrestgoConfig {
  nodeEnv: PrestgoEnvironment;
  apiPort: number;
  databaseUrl: string;
  redisUrl: string;
  accessTokenSecret: string;
  refreshTokenSecret: string;
  fileStorageRoot: string;
}

const DEFAULT_PORT = 3000;

function readRequired(name: string, source: NodeJS.ProcessEnv): string {
  const value = source[name];

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

function readPort(source: NodeJS.ProcessEnv): number {
  const raw = source.API_PORT ?? String(DEFAULT_PORT);
  const parsed = Number(raw);

  if (!Number.isInteger(parsed) || parsed <= 0 || parsed > 65535) {
    throw new Error("API_PORT must be a valid TCP port");
  }

  return parsed;
}

export function loadConfig(source: NodeJS.ProcessEnv = process.env): PrestgoConfig {
  return {
    nodeEnv: (source.NODE_ENV as PrestgoEnvironment | undefined) ?? "development",
    apiPort: readPort(source),
    databaseUrl: readRequired("DATABASE_URL", source),
    redisUrl: readRequired("REDIS_URL", source),
    accessTokenSecret: readRequired("ACCESS_TOKEN_SECRET", source),
    refreshTokenSecret: readRequired("REFRESH_TOKEN_SECRET", source),
    fileStorageRoot: source.FILE_STORAGE_ROOT ?? "storage/files"
  };
}
