export interface TestUser {
  id: string;
  email: string;
  roles: string[];
}

export function createTestUser(overrides: Partial<TestUser> = {}): TestUser {
  return {
    id: "test-user-id",
    email: "admin@prestgo.test",
    roles: ["super_admin"],
    ...overrides
  };
}

export function expectDefined<T>(value: T | null | undefined, label = "value"): T {
  if (value === null || value === undefined) {
    throw new Error(`Expected ${label} to be defined`);
  }

  return value;
}
