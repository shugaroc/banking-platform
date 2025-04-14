import { ComponentFixture, TestBed } from '@angular/core/testing';

import { UnauthourizedComponent } from './unauthourized.component';

describe('UnauthourizedComponent', () => {
  let component: UnauthourizedComponent;
  let fixture: ComponentFixture<UnauthourizedComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [UnauthourizedComponent]
    })
    .compileComponents();
    
    fixture = TestBed.createComponent(UnauthourizedComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
