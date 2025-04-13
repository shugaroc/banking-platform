import { Injectable } from '@angular/core';
import {
  createClient,
  SupabaseClient,
  AuthChangeEvent,
  Session,
  User,
  PostgrestClient,
} from '@supabase/supabase-js';
import { environment } from '../../environments/environment';

@Injectable({
  providedIn: 'root',
})
export class SupabaseService {
  private supabase: SupabaseClient;

  constructor() {
    this.supabase = createClient(environment.supabaseUrl, environment.supabaseKey);
  }

  get auth(): {
    onAuthStateChange: (callback: (event: AuthChangeEvent, session: Session | null) => void) => {
      data: { subscription: { unsubscribe: () => void } };
    };
    signUp: (credentials: {
      email: string;
      password: string;
    }) => Promise<{ user: User | null; error: Error | null }>;
    signIn: (credentials: {
      email: string;
      password: string;
    }) => Promise<{ user: User | null; error: Error | null }>;
    signOut: () => Promise<{ error: Error | null }>;
  } {
    return this.supabase.auth;
  }

  get db(): PostgrestClient {
    return this.supabase;
  }
}
