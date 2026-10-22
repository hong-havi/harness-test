// 백엔드 응답 계약 (task.md Design §API 계약 / Implementation (Backend)).
// 모든 필드는 camelCase, id 는 bigint → 문자열.

/** POST /auth/signup, POST /auth/login 응답 바디 */
export interface PublicMember {
  id: string;
  userId: string;
  nickname: string;
}

/** GET /members/me, PATCH /members/me 응답 바디 */
export interface MemberProfile {
  id: string;
  userId: string;
  nickname: string;
  createdAt: string;
  updatedAt: string;
}

/** POST /auth/signup 요청 바디 */
export interface SignupInput {
  userId: string;
  password: string;
  nickname: string;
}

/** POST /auth/login 요청 바디 */
export interface LoginInput {
  userId: string;
  password: string;
}

/** POST /auth/join 요청 바디 (nickname 은 서버가 자동 생성) */
export interface JoinInput {
  userId: string;
  password: string;
}

/**
 * PATCH /members/me 요청 바디.
 * 전부 optional, 최소 1개 필드. newPassword 제공 시 currentPassword 필수.
 */
export interface UpdateMeInput {
  nickname?: string;
  newPassword?: string;
  currentPassword?: string;
}
