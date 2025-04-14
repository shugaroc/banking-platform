import { Injectable } from '@angular/core';
import { BehaviorSubject, Observable, from, throwError } from 'rxjs';
import { map, catchError, tap, switchMap } from 'rxjs/operators';
import { AuthResponse, Session, User, UserResponse } from '@supabase/supabase-js';
import { LoginCredentials, SignUpCredentials, AuthState } from '../models/auth.model';
import { SupabaseService } from '@core/services/supabase.service';

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private currentUserSubject = new BehaviorSubject<User | null>(null);
  private sessionSubject = new BehaviorSubject<Session | null>(null);

  constructor(private supabase: SupabaseService) {
    // Listen for auth state changes
    this.supabase.onAuthStateChange((event, session) => {
      this.sessionSubject.next(session);
      this.currentUserSubject.next(session?.user ?? null);
    });
  }

  get currentUser$(): Observable<User | null> {
    return this.currentUserSubject.asObservable();
  }

  get session$(): Observable<Session | null> {
    return this.sessionSubject.asObservable();
  }

  signUp({ email, password }: SignUpCredentials): Observable<AuthResponse> {
    return from(this.supabase.signUp(email, password)).pipe(
      tap(({ data: { session, user } }) => {
        if (session) {
          this.sessionSubject.next(session);
          this.currentUserSubject.next(user);
        }
      }),
      catchError(error => throwError(() => error))
    );
  }

  confirmSignup(email: string, token: string): Observable<AuthResponse> {
    return from(this.supabase.auth.verifyOtp({
      email,
      token,
      type: 'email'
    })).pipe(
      tap(({ data: { session, user } }) => {
        if (session) {
          this.sessionSubject.next(session);
          this.currentUserSubject.next(user);
        }
      }),
      catchError(error => throwError(() => error))
    );

  }

  signIn({ email, password }: LoginCredentials): Observable<AuthResponse> {
    return from(this.supabase.signIn(email, password)).pipe(
      tap(({ data: { session, user } }) => {
        this.sessionSubject.next(session);
        this.currentUserSubject.next(user);
      }),
      catchError(error => throwError(() => error))
    );
  }

  signOut(): Observable<void> {
    return from(this.supabase.signOut()).pipe(
      tap(() => {
        this.sessionSubject.next(null);
        this.currentUserSubject.next(null);
      }),
      map(() => void 0),
      catchError(error => throwError(() => error))
    );
  }

  /**
   * Initiates the forgot password flow by sending a reset link
   * @param email User's email address
   */
  forgotPassword(email: string): Observable<{ data: object | null; error: Error | null }> {
    return from(this.supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/auth/reset-password`
    })).pipe(
      tap(() => {
        // Clear current session since user is resetting password
        this.sessionSubject.next(null);
        this.currentUserSubject.next(null);
      }),
      catchError(error => throwError(() => error))
    );
  }

  /**
   * Updates user's password after they've clicked the reset link
   * @param newPassword New password to set
   */
  updatePassword(email: string, newPassword: string): Observable<UserResponse> {
    return from(this.supabase.auth.updateUser({ 
      email,
      password: newPassword 
    })).pipe(
      tap(({ data: { user } }) => {
        if (user) {
          this.currentUserSubject.next(user);
        }
      }),
      catchError(error => throwError(() => error))
    );
  }

  verifyOTP(email: string, token: string): Observable<AuthResponse> {
    return from(this.supabase.auth.verifyOtp({
      email,
      token,
      type: 'email'
    })).pipe(
      tap(({ data: { session, user } }) => {
        if (session) {
          this.sessionSubject.next(session);
          this.currentUserSubject.next(user);
        }
      }),
      catchError(error => throwError(() => error))
    );
  }

  verifyEmail(token: string): Observable<any> {
    return from(this.supabase.auth.verifyOtp({ 
      token_hash: token, 
      type: 'email' 
    })).pipe(
      catchError(error => {
        console.error('Email verification failed:', error);
        return throwError(() => new Error('Email verification failed. Please try again.'));
      })
    );
  }

  resendVerificationEmail(email: string): Observable<any> {
    return from(this.supabase.auth.resend({
      type: 'signup',
      email: email
    })).pipe(
      catchError(error => {
        console.error('Failed to resend verification email:', error);
        return throwError(() => new Error('Failed to send verification email. Please try again.'));
      })
    );
  }
}
