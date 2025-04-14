import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatIconModule } from '@angular/material/icon';  // Add this import
import { AuthService } from '../services/auth.service';

@Component({
  selector: 'app-verify-email',
  standalone: true,
  imports: [
    CommonModule,
    RouterModule,
    MatCardModule,
    MatButtonModule,
    MatProgressSpinnerModule,
    MatIconModule,  // Add this to imports array
  ],
  templateUrl: './verify-email.component.html',
  styleUrls: ['../styles/auth-shared.scss']
})
export class VerifyEmailComponent implements OnInit {
  isLoading = false;
  errorMessage = '';
  successMessage = '';
  email = '';

  constructor(
    private authService: AuthService,
    private route: ActivatedRoute,
    private router: Router
  ) {}

  ngOnInit() {
    // Get verification token from URL if present
    const token = this.route.snapshot.queryParams['token'];
    if (token) {
      this.verifyEmail(token);
    }
    
    // Get email from auth service or route
    this.email = this.route.snapshot.queryParams['email'] || '';
  }

  verifyEmail(token: string) {
    this.isLoading = true;
    this.errorMessage = '';
    
    this.authService.verifyEmail(token).subscribe({
      next: () => {
        this.successMessage = 'Email verified successfully! You can now login.';
        setTimeout(() => this.router.navigate(['/auth/login']), 3000);
      },
      error: (error) => {
        this.errorMessage = error.message || 'Verification failed. Please try again.';
      },
      complete: () => {
        this.isLoading = false;
      }
    });
  }

  resendVerification() {
    if (!this.email) {
      this.errorMessage = 'Email address is required';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    
    this.authService.resendVerificationEmail(this.email).subscribe({
      next: () => {
        this.successMessage = 'Verification email sent successfully!';
      },
      error: (error) => {
        this.errorMessage = error.message || 'Failed to send verification email';
      },
      complete: () => {
        this.isLoading = false;
      }
    });
  }
}
