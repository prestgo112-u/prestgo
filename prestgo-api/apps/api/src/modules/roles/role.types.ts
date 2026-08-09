export interface RoleDto {
  id: string;
  code: string;
  name: string;
  description?: string;
  isSystem: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface PermissionDto {
  id: string;
  code: string;
  module: string;
  action: string;
  description?: string;
}

export interface RoleWithPermissions extends RoleDto {
  permissions: PermissionDto[];
}

export interface CreateRoleDto {
  code: string;
  name: string;
  description?: string;
  permissionIds?: string[];
}

export interface UpdateRoleDto {
  name?: string;
  description?: string;
  permissionIds?: string[];
}

export interface AssignPermissionsDto {
  permissionIds: string[];
}
