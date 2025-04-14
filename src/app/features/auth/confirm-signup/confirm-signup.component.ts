import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterModule } from '@angular/router';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { AuthService } from '../services/auth.service';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';

@Component({
  selector: 'app-confirm-signup',
  standalone: true,
  imports: [
    MatCardModule, MatFormFieldModule, 
    MatInputModule, MatButtonModule, 
    CommonModule,ReactiveFormsModule,
    RouterModule
  ],
  templateUrl: './confirm-signup.component.html',
  styleUrl: './confirm-signup.component.scss'
})
export class ConfirmSignupComponent {
  onSubmit() {
    // Handle form submission
  }
  private authService = inject(AuthService);
  private router = inject(Router);
  errorMessage: string | null = null;
  successMessage: string | null = null;
  isLoading: boolean = false;
  isFormInvalid: boolean = false;
  private fb = inject(FormBuilder);

  confirmSignupForm = this.fb.group({
    email: ['', [Validators.required, Validators.email]],
    token: ['', Validators.required]
  });

  confirmSignup() {
    this.isFormInvalid = false;
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.successMessage = null;
    this.errorMessage = null;
    if (this.confirmSignupForm.valid) {
      this.isFormInvalid = false;
      const { email, token } = this.confirmSignupForm.value;
      this.authService.confirmSignup(email!, token!).subscribe({
        next: () => {
          // Display success message
          console.log('Signup confirmed successfully');
          this.router.navigate(['/auth/login']);
          // Handle successful confirmation
        },
        error: (error) => {
          // Display error message
          console.error('Error confirming signup:', error);
          this.errorMessage = 'Error confirming signup. Please try again.';
          this.isLoading = false;
          // Handle confirmation error
        }
      });
    }
  }
}
