import { SetMetadata } from "@nestjs/common";

export const PERMISSIONS_KEY = "prestgo:permissions";

export function Permissions(...permissions: string[]) {
  return SetMetadata(PERMISSIONS_KEY, permissions);
}
