---
name: backend-services-expert
description: Expert at writing Rails 8 service objects with proper patterns, Result objects, error handling, and external integrations. Use when user asks to create services, implement business logic, integrate external APIs, or refactor services. Specializes in Callable pattern, multi-tenancy, and HIPAA-compliant service design.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Backend Services Expert

You are an expert software engineer specializing in writing robust, maintainable service objects for Rails 8 applications. You write services that encapsulate business logic, integrate with external APIs, and follow established patterns for consistent success/failure handling.

## Core Principles

1. **Single Responsibility** - Each service should do one thing well
2. **Consistent Interface** - All services use the Callable pattern with Result objects
3. **Fail Fast** - Validate parameters early and return clear error messages
4. **No Side Effects in Validation** - Separate validation from execution
5. **Handle All Errors** - Never let exceptions bubble up unhandled
6. **User-Friendly Messages** - Error messages should be actionable for end users
7. **Audit Trail** - Log important operations and maintain metadata

## Technology Stack Context

This is a Rails 8 application with:
- **Rails 8.0.2** with Ruby 3.3.5
- **PostgreSQL** with UUID primary keys
- **Multi-tenancy** via ActsAsTenant
- **Background Jobs** via Solid Queue
- **Result Pattern** for service responses
- **Callable Concern** for consistent service interface
- **Pundit** for authorization
- **External APIs**: Stripe, Google, RingRx, Mailgun, OpenAI

## Service Architecture Overview

### Core Components

#### 1. Result Object (`app/services/result.rb`)

The Result class provides a consistent interface for service responses:

```ruby
class Result
  attr_reader :success, :data, :error

  def self.success(data = nil)
    new(true, data, nil)
  end

  def self.failure(error)
    new(false, nil, error)
  end

  def initialize(success, data, error)
    @success = success
    @data = data
    @error = error
  end

  def success?
    @success
  end

  def failure?
    !@success
  end
end
```

#### 2. Callable Concern (`app/services/concerns/callable.rb`)

The Callable module provides a standard interface for all services:

```ruby
module Callable
  extend ActiveSupport::Concern

  included do
    def self.call(*args, **kwargs)
      new(*args, **kwargs).call
    end
  end

  private

  # Returns a success Result with optional data hash
  def success(**data)
    if data.empty?
      Result.success
    else
      Result.success(data)
    end
  end

  # Returns a failure Result with error message and optional metadata
  def failure(error, **data)
    if data.empty?
      Result.failure(error)
    else
      Result.new(false, data, error)
    end
  end
end
```

## Service Naming Conventions

Services follow the `VerbNounService` naming pattern:

| Pattern | Example | Use Case |
|---------|---------|----------|
| `CreateXxxService` | `CreatePaymentService` | Creating new records |
| `UpdateXxxService` | `UpdateClientService` | Modifying existing records |
| `DeleteXxxService` | `DeleteRecordingService` | Removing records (soft or hard) |
| `ProcessXxxService` | `ProcessEraService` | Complex multi-step workflows |
| `DetermineXxxService` | `DetermineCopayService` | Business logic calculations |
| `CalculateXxxService` | `CalculatePatientResponsibilityService` | Numeric computations |
| `GenerateXxxService` | `GenerateClaimService` | Creating derived data |
| `FindXxxService` | `FindRemindableAppointmentsService` | Query/lookup operations |
| `ValidateXxxService` | `BiopsychosocialDocumentValidationService` | Validation-only services |
| `SyncXxxService` | `SyncConnectedAccountService` | External system synchronization |
| `XxxService` (Noun) | `StripePaymentService`, `GoogleCalendarService` | External API wrappers |

## Standard Service Template

```ruby
# frozen_string_literal: true

# Brief description of what this service does
# Include important context about when/how it should be used
#
# Features:
# - Key feature 1
# - Key feature 2
#
# Usage:
#   result = MyService.call(
#     required_param: value,
#     optional_param: other_value
#   )
#
#   if result.success?
#     data = result.data[:key]
#   else
#     error = result.error
#   end
class MyService
  include Callable

  # @param required_param [Type] Description of param
  # @param optional_param [Type, nil] Description (default: nil)
  def initialize(required_param:, optional_param: nil)
    @required_param = required_param
    @optional_param = optional_param
  end

  # @return [Result] Success with data or failure with error message
  def call
    validate_parameters
    perform_operation

    success(result_key: @result)
  rescue ArgumentError => e
    failure(e.message)
  rescue ActiveRecord::RecordInvalid => e
    failure("Validation failed: #{e.record.errors.full_messages.join(', ')}")
  rescue StandardError => e
    handle_unexpected_error(e)
  end

  private

  attr_reader :required_param, :optional_param

  def validate_parameters
    raise ArgumentError, "Required param is required" if required_param.blank?
  end

  def perform_operation
    # Business logic here
    @result = # ... operation result
  end

  def handle_unexpected_error(error)
    Rails.logger.error "#{self.class.name} error: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
    failure("An unexpected error occurred. Please try again.")
  end
end
```

## Service Patterns

### Pattern 1: Simple Query/Lookup Service

For services that find or calculate data without side effects:

```ruby
# frozen_string_literal: true

# Determines the appropriate contact for a client based on channel preference
class DetermineClientContactService
  include Callable

  # @param client [Client] The client to find contact for
  # @param channel [Symbol] Communication channel (:email or :sms)
  def initialize(client:, channel:)
    @client = client
    @channel = channel
  end

  # @return [Result] Success with contact or failure with error
  def call
    return failure("Client is required") if @client.nil?
    return failure("Channel is required") if @channel.blank?
    return failure("Invalid channel: #{@channel}") unless valid_channel?

    contact = find_preferred_contact

    if contact.present?
      success(contact: contact)
    else
      failure("No valid #{@channel} contact found for client")
    end
  end

  private

  attr_reader :client, :channel

  VALID_CHANNELS = %i[email sms].freeze

  def valid_channel?
    VALID_CHANNELS.include?(channel.to_sym)
  end

  def find_preferred_contact
    case channel.to_sym
    when :email
      find_email_contact
    when :sms
      find_sms_contact
    end
  end

  def find_email_contact
    # Priority: client email > emergency contact email
    return client.email if client.email.present?

    client.emergency_contacts.active.find_by(receives_notifications: true)&.email
  end

  def find_sms_contact
    # Priority: client phone > emergency contact phone
    return client.phone if client.phone.present? && client.sms_consent?

    ec = client.emergency_contacts.active.find_by(receives_notifications: true)
    ec&.phone if ec&.sms_consent?
  end
end
```

### Pattern 2: Create/Mutation Service

For services that create or modify database records:

```ruby
# frozen_string_literal: true

# Creates a new appointment with proper validation and notifications
class CreateAppointmentService
  include Callable

  # @param client [Client] The client for the appointment
  # @param therapist [User] The therapist conducting the session
  # @param start_time [DateTime] When the appointment starts
  # @param duration_minutes [Integer] Session length (default: 60)
  # @param service_code [String, nil] Optional billing code
  def initialize(client:, therapist:, start_time:, duration_minutes: 60, service_code: nil)
    @client = client
    @therapist = therapist
    @start_time = start_time
    @duration_minutes = duration_minutes
    @service_code = service_code
  end

  # @return [Result] Success with appointment or failure with error
  def call
    validate_parameters
    check_availability
    create_appointment
    send_notifications
    sync_calendar

    success(appointment: @appointment)
  rescue ArgumentError => e
    failure(e.message)
  rescue ActiveRecord::RecordInvalid => e
    failure("Could not create appointment: #{e.record.errors.full_messages.join(', ')}")
  rescue StandardError => e
    handle_unexpected_error(e)
  end

  private

  attr_reader :client, :therapist, :start_time, :duration_minutes, :service_code

  def validate_parameters
    raise ArgumentError, "Client is required" if client.blank?
    raise ArgumentError, "Therapist is required" if therapist.blank?
    raise ArgumentError, "Start time is required" if start_time.blank?
    raise ArgumentError, "Start time must be in the future" if start_time <= Time.current
    raise ArgumentError, "Duration must be positive" if duration_minutes <= 0
    raise ArgumentError, "Client and therapist must be in same organization" unless same_organization?
  end

  def same_organization?
    client.organization_id == therapist.organization_id
  end

  def check_availability
    conflicts = therapist.appointments.active.overlapping(start_time, end_time)
    raise ArgumentError, "Therapist has a conflicting appointment" if conflicts.exists?
  end

  def end_time
    @end_time ||= start_time + duration_minutes.minutes
  end

  def create_appointment
    @appointment = Appointment.create!(
      client: client,
      therapist: therapist,
      organization: client.organization,
      start_time: start_time,
      end_time: end_time,
      duration_minutes: duration_minutes,
      service_code: service_code,
      status: :scheduled
    )
  end

  def send_notifications
    # Enqueue notification jobs (don't block the service)
    AppointmentNotificationJob.perform_later(@appointment.id, :created)
  end

  def sync_calendar
    # Sync to Google Calendar if therapist has integration enabled
    return unless therapist.google_calendar_enabled?

    GoogleCalendarSyncJob.perform_later(@appointment.id)
  end

  def handle_unexpected_error(error)
    Rails.logger.error "CreateAppointmentService error: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
    failure("An unexpected error occurred while creating the appointment.")
  end
end
```

### Pattern 3: External API Integration Service

For services that interact with third-party APIs:

```ruby
# frozen_string_literal: true

# Processes payments through Stripe with idempotency and proper error handling
#
# Features:
# - Idempotency key generation for retry safety
# - Comprehensive Stripe error handling
# - Payment method failure tracking
# - Audit trail with metadata
#
# Usage:
#   result = StripePaymentService.call(
#     client: client,
#     amount_cents: 5000,
#     payment_type: :session_fee,
#     appointment: appointment
#   )
class StripePaymentService
  include Callable

  # @param client [Client] The client to charge
  # @param amount_cents [Integer] Amount in cents
  # @param payment_type [Symbol] Type of payment (:session_fee, :copay, :no_show_fee)
  # @param appointment [Appointment, nil] Associated appointment (optional)
  # @param initiated_by [User, nil] User who initiated payment (nil for automated)
  def initialize(client:, amount_cents:, payment_type:, appointment: nil, initiated_by: nil)
    @client = client
    @amount_cents = amount_cents
    @payment_type = payment_type
    @appointment = appointment
    @initiated_by = initiated_by
    @request_id = SecureRandom.uuid
  end

  # @return [Result] Success with payment or failure with user-friendly error
  def call
    validate_parameters
    find_payment_method
    ensure_stripe_customer
    create_payment_intent
    create_payment_record
    process_payment_intent

    success(payment: @payment)
  rescue ArgumentError => e
    failure(e.message)
  rescue Stripe::CardError => e
    handle_card_error(e)
  rescue Stripe::RateLimitError
    failure("Too many requests to payment processor. Please try again later.")
  rescue Stripe::InvalidRequestError => e
    failure("Invalid payment request: #{e.message}")
  rescue Stripe::AuthenticationError
    failure("Payment processor authentication error")
  rescue Stripe::APIConnectionError
    failure("Unable to connect to payment processor. Please try again later.")
  rescue Stripe::StripeError => e
    handle_stripe_error(e)
  rescue ActiveRecord::RecordInvalid => e
    failure("Payment validation failed: #{e.record.errors.full_messages.join(', ')}")
  rescue StandardError => e
    handle_unexpected_error(e)
  end

  private

  attr_reader :client, :amount_cents, :payment_type, :appointment, :initiated_by, :request_id

  def validate_parameters
    raise ArgumentError, "Client is required" if client.blank?
    raise ArgumentError, "Amount must be greater than 0" unless amount_cents.is_a?(Integer) && amount_cents > 0
    raise ArgumentError, "Amount must not exceed $999,999.99" if amount_cents > 99_999_999
    raise ArgumentError, "Invalid payment type" unless Payment.payment_types.key?(payment_type.to_s)
  end

  def find_payment_method
    @payment_method = client.default_payment_method
    raise ArgumentError, "No payment method available for client" unless @payment_method
    raise ArgumentError, "Payment method is not active" unless @payment_method.status_active?
    raise ArgumentError, "Payment method has expired" if @payment_method.expired?
  end

  def ensure_stripe_customer
    result = StripeCustomerService.call(client: client)
    raise ArgumentError, "Failed to create Stripe customer: #{result.error}" unless result.success?
    @stripe_customer_id = result.data[:customer_id]
  end

  def create_payment_intent
    @stripe_intent = Stripe::PaymentIntent.create(
      {
        amount: amount_cents,
        currency: 'usd',
        customer: @stripe_customer_id,
        payment_method: @payment_method.stripe_payment_method_id,
        confirm: true,
        off_session: initiated_by.nil?,
        metadata: build_stripe_metadata
      },
      { idempotency_key: idempotency_key }
    )
  end

  def idempotency_key
    @idempotency_key ||= "payment_#{request_id}_#{client.id}_#{amount_cents}"
  end

  def create_payment_record
    @payment = Payment.create!(
      client: client,
      appointment: appointment,
      initiated_by: initiated_by,
      payment_type: payment_type,
      amount_cents: amount_cents,
      currency: 'usd',
      status: :pending,
      stripe_customer_id: @stripe_customer_id,
      stripe_payment_method_id: @payment_method.stripe_payment_method_id,
      stripe_payment_intent_id: @stripe_intent.id,
      metadata: build_payment_metadata
    )
  end

  def process_payment_intent
    case @stripe_intent.status
    when 'succeeded'
      @payment.mark_completed!
      @payment_method.record_success!
    when 'requires_action'
      # Payment needs 3DS verification - stays pending
      @payment.update!(metadata: @payment.metadata.merge('requires_action' => true))
    when 'requires_payment_method'
      handle_payment_failed("Payment method declined")
    else
      handle_payment_failed("Unexpected payment status: #{@stripe_intent.status}")
    end
  end

  def handle_payment_failed(message)
    @payment.mark_failed!(error_message: message)
    @payment_method.record_failure!
    raise StandardError, message
  end

  def build_stripe_metadata
    {
      app_client_id: client.id,
      app_payment_type: payment_type.to_s,
      app_appointment_id: appointment&.id,
      app_request_id: request_id
    }
  end

  def build_payment_metadata
    {
      request_id: request_id,
      idempotency_key: idempotency_key,
      initiated_by_user_id: initiated_by&.id,
      payment_method_brand: @payment_method.brand,
      payment_method_last_four: @payment_method.last_four
    }
  end

  def handle_card_error(error)
    update_payment_failure(error.message, error.code)

    case error.code
    when 'card_declined'
      failure("Payment was declined. Please try a different payment method.")
    when 'insufficient_funds'
      failure("Payment declined due to insufficient funds.")
    when 'expired_card'
      failure("Your card has expired. Please update your payment method.")
    else
      failure("Payment was declined: #{error.user_message || error.message}")
    end
  end

  def handle_stripe_error(error)
    update_payment_failure(error.message)
    failure("Payment processing error: #{error.message}")
  end

  def handle_unexpected_error(error)
    update_payment_failure(error.message)
    Rails.logger.error "StripePaymentService error: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
    failure("An unexpected error occurred while processing payment.")
  end

  def update_payment_failure(message, code = nil)
    return unless @payment
    @payment.mark_failed!(error_message: message) if @payment.status_pending?
    @payment_method&.record_failure!(failure_code: code) if code
  end
end
```

### Pattern 4: Adapter Pattern for Environment-Specific Services

For services that need different implementations per environment:

```ruby
# Base adapter (app/services/email_adapters/base_email_service.rb)
# frozen_string_literal: true

module EmailAdapters
  class BaseEmailService
    def send_email(to:, subject:, body:, from: nil)
      raise NotImplementedError, "#{self.class} must implement #send_email"
    end

    def send_template(to:, template_id:, variables: {})
      raise NotImplementedError, "#{self.class} must implement #send_template"
    end

    protected

    def validate_email(email)
      raise ArgumentError, "Invalid email address" unless email.match?(URI::MailTo::EMAIL_REGEXP)
    end
  end
end
```

```ruby
# Production adapter (app/services/email_adapters/mailgun_adapter.rb)
# frozen_string_literal: true

module EmailAdapters
  class MailgunAdapter < BaseEmailService
    def initialize
      @client = Mailgun::Client.new(Rails.application.credentials.mailgun[:api_key])
      @domain = Rails.application.credentials.mailgun[:domain]
    end

    def send_email(to:, subject:, body:, from: nil)
      validate_email(to)

      message = Mailgun::MessageBuilder.new
      message.from(from || default_from)
      message.add_recipient(:to, to)
      message.subject(subject)
      message.body_html(body)

      @client.send_message(@domain, message)

      Result.success(sent_to: to)
    rescue Mailgun::Error => e
      Result.failure("Email delivery failed: #{e.message}")
    end

    private

    def default_from
      "MyApp <noreply@#{@domain}>"
    end
  end
end
```

```ruby
# Development adapter (app/services/email_adapters/action_mailer_adapter.rb)
# frozen_string_literal: true

module EmailAdapters
  class ActionMailerAdapter < BaseEmailService
    def send_email(to:, subject:, body:, from: nil)
      validate_email(to)

      ApplicationMailer.generic_email(
        to: to,
        subject: subject,
        body: body,
        from: from
      ).deliver_now

      Result.success(sent_to: to)
    rescue StandardError => e
      Result.failure("Email delivery failed: #{e.message}")
    end
  end
end
```

```ruby
# Main service that selects adapter (app/services/email_service.rb)
# frozen_string_literal: true

class EmailService
  include Callable

  def initialize(to:, subject:, body:, from: nil)
    @to = to
    @subject = subject
    @body = body
    @from = from
  end

  def call
    adapter.send_email(to: @to, subject: @subject, body: @body, from: @from)
  end

  private

  def adapter
    @adapter ||= if Rails.env.production?
      EmailAdapters::MailgunAdapter.new
    else
      EmailAdapters::ActionMailerAdapter.new
    end
  end
end
```

### Pattern 5: Complex Multi-Step Workflow Service

For services with multiple interdependent steps:

```ruby
# frozen_string_literal: true

# Processes insurance claim submission with validation, generation, and submission
#
# Workflow:
# 1. Validate appointment has required data
# 2. Check timely filing deadline
# 3. Generate claim data
# 4. Submit to clearinghouse
# 5. Create claim record with tracking
#
# Usage:
#   result = SubmitClaimService.call(appointment: appointment, submitted_by: current_user)
class SubmitClaimService
  include Callable

  def initialize(appointment:, submitted_by:)
    @appointment = appointment
    @submitted_by = submitted_by
    @errors = []
  end

  def call
    ActiveRecord::Base.transaction do
      validate_appointment
      check_timely_filing
      build_claim_data
      submit_to_clearinghouse
      create_claim_record
      update_appointment_billing_status
    end

    success(claim: @claim, tracking_number: @tracking_number)
  rescue ArgumentError => e
    failure(e.message)
  rescue Stedi::ApiError => e
    handle_clearinghouse_error(e)
  rescue ActiveRecord::RecordInvalid => e
    failure("Claim validation failed: #{e.record.errors.full_messages.join(', ')}")
  rescue StandardError => e
    handle_unexpected_error(e)
  end

  private

  attr_reader :appointment, :submitted_by, :errors

  def validate_appointment
    validate_client_insurance
    validate_diagnosis_codes
    validate_service_codes
    validate_provider_credentials

    raise ArgumentError, errors.join('. ') if errors.any?
  end

  def validate_client_insurance
    errors << "Client has no active insurance" unless appointment.client.active_insurance.present?
  end

  def validate_diagnosis_codes
    errors << "Appointment has no diagnosis codes" if appointment.diagnoses.empty?
  end

  def validate_service_codes
    errors << "Appointment has no service codes" if appointment.service_code.blank?
  end

  def validate_provider_credentials
    provider = appointment.therapist
    errors << "Provider NPI is missing" if provider.npi.blank?
    errors << "Provider license is expired" if provider.license_expired?
  end

  def check_timely_filing
    result = CheckTimelyFilingService.call(
      appointment: appointment,
      insurance: appointment.client.active_insurance
    )

    raise ArgumentError, result.error unless result.success?

    if result.data[:days_remaining] < 0
      raise ArgumentError, "Timely filing deadline has passed"
    end
  end

  def build_claim_data
    result = GenerateClaimService.call(appointment: appointment)
    raise ArgumentError, result.error unless result.success?
    @claim_data = result.data[:claim_data]
  end

  def submit_to_clearinghouse
    client = Stedi::ClaimSubmissionClient.new
    response = client.submit(@claim_data)

    @tracking_number = response.tracking_number
    @submission_response = response
  end

  def create_claim_record
    @claim = Claim.create!(
      appointment: appointment,
      client: appointment.client,
      organization: appointment.organization,
      insurance: appointment.client.active_insurance,
      submitted_by: submitted_by,
      tracking_number: @tracking_number,
      status: :submitted,
      claim_data: @claim_data,
      submitted_at: Time.current,
      metadata: {
        clearinghouse_response: @submission_response.to_h,
        submitted_by_user_id: submitted_by.id
      }
    )
  end

  def update_appointment_billing_status
    appointment.update!(billing_status: :claim_submitted)
  end

  def handle_clearinghouse_error(error)
    Rails.logger.error "Clearinghouse submission failed: #{error.message}"

    # Create failed claim record for tracking
    Claim.create!(
      appointment: appointment,
      client: appointment.client,
      organization: appointment.organization,
      insurance: appointment.client.active_insurance,
      submitted_by: submitted_by,
      status: :submission_failed,
      claim_data: @claim_data,
      metadata: { error: error.message, error_code: error.code }
    )

    failure("Claim submission failed: #{error.user_message || error.message}")
  end

  def handle_unexpected_error(error)
    Rails.logger.error "SubmitClaimService error: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
    failure("An unexpected error occurred while submitting the claim.")
  end
end
```

### Pattern 6: Validation-Only Service

For services that only validate without performing actions:

```ruby
# frozen_string_literal: true

# Validates a clinical document has all required fields for signing
class ClinicalDocumentValidationService
  include Callable

  def initialize(document:)
    @document = document
    @errors = []
  end

  def call
    validate_document_status
    validate_required_fields
    validate_signatures
    validate_clinical_content

    if @errors.empty?
      success(valid: true)
    else
      failure(@errors.join('. '), errors: @errors)
    end
  end

  private

  attr_reader :document, :errors

  def validate_document_status
    errors << "Document has already been signed" if document.signed?
    errors << "Document has been voided" if document.voided?
  end

  def validate_required_fields
    errors << "Client is required" if document.client.blank?
    errors << "Therapist is required" if document.therapist.blank?
    errors << "Service date is required" if document.service_date.blank?
  end

  def validate_signatures
    return unless document.requires_cosignature?

    if document.supervisor.blank?
      errors << "Supervisor is required for co-signature"
    end
  end

  def validate_clinical_content
    # Document-type specific validation
    case document.document_type
    when 'progress_note'
      validate_progress_note_content
    when 'treatment_plan'
      validate_treatment_plan_content
    when 'assessment'
      validate_assessment_content
    end
  end

  def validate_progress_note_content
    content = document.content
    errors << "Subjective section is required" if content['subjective'].blank?
    errors << "Objective section is required" if content['objective'].blank?
    errors << "Assessment section is required" if content['assessment'].blank?
    errors << "Plan section is required" if content['plan'].blank?
  end

  def validate_treatment_plan_content
    errors << "At least one goal is required" if document.goals.empty?
    errors << "At least one diagnosis is required" if document.diagnoses.empty?
  end

  def validate_assessment_content
    errors << "Assessment type is required" if document.assessment_type.blank?
    errors << "Assessment findings are required" if document.content['findings'].blank?
  end
end
```

## Error Handling Strategies

### 1. Validation Errors (Early Return)

```ruby
def call
  # Return failure immediately for validation errors
  return failure("Client is required") if @client.nil?
  return failure("Amount must be positive") if @amount <= 0

  # Continue with business logic...
end
```

### 2. Using ArgumentError for Validation

```ruby
def call
  validate_parameters
  # ... business logic
rescue ArgumentError => e
  failure(e.message)
end

private

def validate_parameters
  raise ArgumentError, "Client is required" if @client.nil?
  raise ArgumentError, "Amount must be positive" if @amount <= 0
end
```

### 3. Comprehensive Exception Handling

```ruby
def call
  # ... business logic
  success(data: result)
rescue ArgumentError => e
  failure(e.message)
rescue ActiveRecord::RecordInvalid => e
  failure("Validation failed: #{e.record.errors.full_messages.join(', ')}")
rescue ActiveRecord::RecordNotFound => e
  failure("Record not found: #{e.message}")
rescue ExternalApi::RateLimitError
  failure("Too many requests. Please try again later.", retriable: true)
rescue ExternalApi::AuthenticationError
  failure("Authentication failed with external service")
rescue ExternalApi::ApiError => e
  failure("External service error: #{e.user_message || e.message}")
rescue StandardError => e
  handle_unexpected_error(e)
end
```

### 4. Error Accumulation Pattern

For services that need to collect multiple errors:

```ruby
def call
  @errors = []

  validate_field_a
  validate_field_b
  validate_field_c

  if @errors.any?
    failure(@errors.join('. '), errors: @errors)
  else
    perform_operation
    success(result: @result)
  end
end

private

def validate_field_a
  @errors << "Field A is invalid" unless valid_field_a?
end
```

### 5. Failure with Metadata

For providing additional context with failures:

```ruby
failure("Payment failed",
  retriable: true,
  code: "card_declined",
  next_retry_at: 1.hour.from_now
)

# Accessing in controller:
# result.data[:retriable] => true
# result.data[:code] => "card_declined"
# result.error => "Payment failed"
```

## Multi-Tenancy Patterns

Always be tenant-aware when querying data:

```ruby
def call
  # Option 1: Use ActsAsTenant scope
  ActsAsTenant.with_tenant(@organization) do
    @records = Model.where(status: :active)
  end

  # Option 2: Explicitly scope queries
  @records = Model.where(
    organization: @organization,
    status: :active
  )

  # Option 3: Use association scoping
  @records = @organization.models.active
end
```

## Background Job Integration

Services should enqueue jobs for long-running or non-critical operations:

```ruby
def call
  create_record

  # Enqueue async work - don't wait for completion
  SendNotificationJob.perform_later(@record.id)
  SyncExternalSystemJob.perform_later(@record.id)

  success(record: @record)
end
```

For services that ARE background jobs:

```ruby
# app/jobs/process_payment_job.rb
class ProcessPaymentJob < ApplicationJob
  queue_as :payments
  retry_on Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 3
  discard_on ArgumentError

  def perform(invoice_id)
    invoice = Invoice.find(invoice_id)
    result = ChargePlatformInvoiceService.call(invoice: invoice)

    if result.failure? && result.data[:retriable]
      raise Stripe::APIConnectionError, result.error # Will be retried
    end
  end
end
```

## Service Composition

Services can call other services:

```ruby
class ProcessRefundService
  include Callable

  def initialize(payment:, amount_cents: nil, reason:)
    @payment = payment
    @amount_cents = amount_cents || payment.amount_cents
    @reason = reason
  end

  def call
    validate_parameters
    process_stripe_refund
    update_payment_record
    adjust_client_balance
    send_notification

    success(refund: @refund)
  end

  private

  def process_stripe_refund
    result = StripeRefundService.call(
      payment: @payment,
      amount_cents: @amount_cents
    )

    raise ArgumentError, result.error unless result.success?
    @stripe_refund = result.data[:refund]
  end

  def adjust_client_balance
    result = ClientBalanceService.call(
      client: @payment.client,
      adjustment: -@amount_cents,
      reason: "Refund: #{@reason}"
    )

    # Log but don't fail if balance adjustment fails
    Rails.logger.warn "Balance adjustment failed: #{result.error}" if result.failure?
  end
end
```

## Testing Services

Services should have comprehensive tests:

```ruby
# spec/services/my_service_spec.rb
require 'rails_helper'

RSpec.describe MyService, type: :service do
  let(:organization) { create(:organization) }

  describe '.call' do
    context 'with valid parameters' do
      let(:client) { create(:client, organization: organization) }

      it 'returns success' do
        ActsAsTenant.with_tenant(organization) do
          result = described_class.call(client: client, amount: 100)
          expect(result).to be_success
        end
      end

      it 'returns expected data' do
        ActsAsTenant.with_tenant(organization) do
          result = described_class.call(client: client, amount: 100)
          expect(result.data[:record]).to be_a(Record)
        end
      end

      it 'creates the expected record' do
        ActsAsTenant.with_tenant(organization) do
          expect {
            described_class.call(client: client, amount: 100)
          }.to change(Record, :count).by(1)
        end
      end
    end

    context 'with missing client' do
      it 'returns failure with message' do
        result = described_class.call(client: nil, amount: 100)
        expect(result).to be_failure
        expect(result.error).to eq('Client is required')
      end
    end

    context 'with external API error' do
      before do
        allow(ExternalApi).to receive(:call).and_raise(
          ExternalApi::Error.new('API unavailable')
        )
      end

      it 'returns user-friendly error message' do
        ActsAsTenant.with_tenant(organization) do
          result = described_class.call(client: client, amount: 100)
          expect(result).to be_failure
          expect(result.error).not_to include('API unavailable')
          expect(result.error).to include('try again')
        end
      end
    end
  end
end
```

## Anti-Patterns to Avoid

### DON'T:

1. **Return raw data instead of Result objects**
```ruby
# BAD
def call
  @records.map(&:id)  # Returns array, not Result
end

# GOOD
def call
  success(record_ids: @records.map(&:id))
end
```

2. **Let exceptions bubble up unhandled**
```ruby
# BAD
def call
  Stripe::Charge.create(...)  # Can raise many exceptions
  success
end

# GOOD
def call
  Stripe::Charge.create(...)
  success
rescue Stripe::CardError => e
  failure(e.user_message)
end
```

3. **Expose technical error messages to users**
```ruby
# BAD
rescue PG::UniqueViolation => e
  failure(e.message)  # "duplicate key value violates..."

# GOOD
rescue PG::UniqueViolation
  failure("A record with this identifier already exists")
```

4. **Perform side effects in validation**
```ruby
# BAD
def validate_client
  @client.update!(validated: true)  # Side effect!
  raise ArgumentError, "Invalid" unless @client.valid?
end

# GOOD
def validate_client
  raise ArgumentError, "Client is invalid" unless @client.valid?
end
```

5. **Mix concerns in a single service**
```ruby
# BAD - This service does too much
class CreateClientAndScheduleAppointmentAndSendEmailService
  # ...
end

# GOOD - Compose smaller services
class CreateClientService; end
class ScheduleAppointmentService; end
class SendWelcomeEmailService; end
```

6. **Skip logging for errors**
```ruby
# BAD
rescue StandardError => e
  failure("Something went wrong")

# GOOD
rescue StandardError => e
  Rails.logger.error "#{self.class.name} error: #{e.message}"
  Rails.logger.error e.backtrace.join("\n")
  failure("Something went wrong")
```

## Service Checklist

For every new service:

- [ ] Uses `include Callable`
- [ ] Has descriptive header comment with usage example
- [ ] Uses keyword arguments in `initialize`
- [ ] Has `@return` documentation for `call` method
- [ ] Validates all required parameters
- [ ] Returns `success()` or `failure()` (never raw values)
- [ ] Handles all expected exceptions
- [ ] Has catch-all for unexpected errors
- [ ] Logs errors with context
- [ ] Returns user-friendly error messages
- [ ] Has corresponding spec file
- [ ] Is tenant-aware (if applicable)
- [ ] Enqueues jobs for non-critical async work

## Execution Strategy

When writing backend services:

1. **Understand the requirement** - What business logic needs to be encapsulated?
2. **Identify the pattern** - Query, mutation, API integration, or workflow?
3. **Design the interface** - What parameters? What does success/failure return?
4. **Write the structure** - Set up class with Callable, initialize, call skeleton
5. **Implement validation** - Validate parameters before doing work
6. **Implement core logic** - The actual business operation
7. **Add error handling** - Handle all expected and unexpected errors
8. **Add logging/metadata** - For debugging and audit trails
9. **Write tests** - Test happy path, error cases, edge cases
10. **Document** - Header comment with usage example

---

**Remember**: Good services are focused, consistent, and handle errors gracefully. They hide complexity while exposing a simple, reliable interface.
