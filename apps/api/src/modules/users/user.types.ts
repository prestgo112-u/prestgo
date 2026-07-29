export interface UserDto {
  id: string;
  firstName?: string;
  lastName?: string;
  phone?: string;
  email?: string;
  status: UserStatus;
  phoneVerifiedAt?: Date;
  emailVerifiedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export enum UserStatus {
  DRAFT = "draft",
  PENDING = "pending",
  ACTIVE = "active",
  REJECTED = "rejected",
  SUSPENDED = "suspended",
  DELETED = "deleted"
}

export interface CreateUserDto {
  firstName?: string;
  lastName?: string;
  phone?: string;
  email?: string;
  password: string;
}

export interface UpdateUserStatusDto {
  status: UserStatus;
  reason: string;
}

export interface UserListQuery {
  page?: number;
  limit?: number;
  /** Champ de tri, confronté à une liste blanche côté service (§15.4). */
  sort?: string;
  status?: UserStatus;
  search?: string;
}

export interface UserWithRoles extends UserDto {
  roles: string[];
  permissions: string[];
}
