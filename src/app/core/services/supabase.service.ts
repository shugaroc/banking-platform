import { Injectable } from '@angular/core';
import {
  createClient,
  SupabaseClient,
  AuthChangeEvent,
  Session,
  User,
  AuthResponse
} from '@supabase/supabase-js';
import { environment } from '../../../environments/environment.development';

@Injectable({
  providedIn: 'root',
})
export class SupabaseService {
  private supabase: SupabaseClient;

  constructor() {
    this.supabase = createClient(environment.supabaseUrl, environment.supabaseKey);
  }

  get auth() {
    return this.supabase.auth;
  }

  get db() {
    return this.supabase;
  }

  async signUp(email: string, password: string): Promise<AuthResponse> {
    return await this.auth.signUp({
      email,
      password
    });
  }

  async signIn(email: string, password: string): Promise<AuthResponse> {
    return await this.auth.signInWithPassword({
      email,
      password
    });
  }

  async signOut(): Promise<{ error: Error | null }> {
    return await this.auth.signOut();
  }

  onAuthStateChange(callback: (event: AuthChangeEvent, session: Session | null) => void) {
    return this.auth.onAuthStateChange(callback);
  }
}
