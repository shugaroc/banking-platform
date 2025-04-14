export interface LoginCredentials {
  email: string;
  password: string;
}

export interface SignUpCredentials extends LoginCredentials {
  confirmPassword: string;
}

export interface PasswordReset {
  email: string;
}

export interface UpdatePasswordRequest {
  newPassword: string;
  confirmPassword: string;
}

export interface OtpVerification {
  email: string;
  token: string;
}

export interface AuthState {
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
}
