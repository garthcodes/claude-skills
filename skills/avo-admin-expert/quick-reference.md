# Avo Admin Quick Reference

## Generate Resource

```bash
rails generate avo:resource Client
```

## Field Types Cheat Sheet

```ruby
# Basic
field :name, as: :text
field :description, as: :textarea
field :content, as: :trix                  # Rich text
field :is_active, as: :boolean
field :count, as: :number
field :password, as: :password

# Date/Time
field :created_at, as: :datetime
field :birth_date, as: :date
field :start_time, as: :time

# Selection
field :status, as: :select, enum: Model::STATUSES
field :status, as: :badge, map: { active: :success, inactive: :danger }
field :tags, as: :tags

# Associations
field :organization, as: :belongs_to, searchable: true
field :items, as: :has_many
field :profile, as: :has_one

# Files
field :avatar, as: :file
field :documents, as: :files

# Special
field :id, as: :id
```

## Common Field Options

```ruby
field :name, as: :text,
  sortable: true,
  link_to_record: true,
  readonly: true,
  placeholder: 'Enter name',
  help: 'Help text',
  hide_on: [:index],
  show_on: [:show, :edit],
  visible: -> { current_user.admin? },
  format_using: -> { value.upcase }
```

## Resource Template

```ruby
class Avo::Resources::Model < Avo::BaseResource
  self.title = :name
  self.includes = [:association1, :association2]

  self.search = {
    query: -> {
      query.ransack(name_cont: params[:q], m: 'or').result(distinct: false)
    }
  }

  def fields
    main_panel do
      field :id, as: :id
      field :name, as: :text, sortable: true
      field :status, as: :badge, map: { active: :success, inactive: :warning }
      field :created_at, as: :datetime, sortable: true, readonly: true

      sidebar do
        field :organization, as: :belongs_to
        field :items, as: :has_many
      end
    end
  end

  def actions
    action Avo::Actions::SoftDelete
    action Avo::Actions::Restore
  end

  def filters
    filter Avo::Filters::SoftDeleteStatusFilter
  end
end
```

## Action Template

```ruby
class Avo::Actions::DoSomething < Avo::BaseAction
  self.name = 'Do Something'
  self.message = 'Are you sure?'
  self.confirm_button_label = 'Yes, Do It'
  self.cancel_button_label = 'Cancel'

  # Optional: standalone (no records needed)
  # self.standalone = true

  # Optional: visibility control
  self.visible = -> {
    view.index? && resource.model_class.included_modules.include?(SomeConcern)
  }

  # Optional: authorization
  self.authorize = -> { current_user.admin? }

  # Optional: form fields
  def fields
    field :reason, as: :textarea
  end

  def handle(query:, fields:, current_user:, resource:, **args)
    count = 0
    query.each do |record|
      # Do something with record
      count += 1
    end
    succeed "Processed #{count} record(s)."
  end
end
```

## Filter Templates

### Select Filter
```ruby
class Avo::Filters::StatusFilter < Avo::Filters::SelectFilter
  self.name = 'Status'

  def apply(request, query, value)
    case value
    when 'active' then query.where(status: :active)
    when 'inactive' then query.where(status: :inactive)
    else query
    end
  end

  def options
    { 'Active' => 'active', 'Inactive' => 'inactive', 'All' => 'all' }
  end

  def default
    'active'
  end
end
```

### Boolean Filter
```ruby
class Avo::Filters::IncludeArchived < Avo::Filters::BooleanFilter
  self.name = 'Include Archived'

  def apply(request, query, value)
    value['archived'] ? query.unscoped : query
  end

  def options
    { archived: 'Show archived' }
  end
end
```

## Dashboard Template

```ruby
class Avo::Dashboards::Overview < Avo::Dashboards::BaseDashboard
  self.id = 'overview'
  self.name = 'Overview'
  self.description = 'Platform metrics'
  self.grid_cols = 4

  def cards
    divider label: 'Section'
    card Avo::Cards::MetricOne, cols: 1
    card Avo::Cards::MetricTwo, cols: 1
  end
end
```

## Card Templates

### Metric Card
```ruby
class Avo::Cards::TotalCount < Avo::Cards::MetricCard
  self.id = 'total_count'
  self.label = 'Total Count'
  self.suffix = 'items'
  # self.prefix = '$'

  def query
    count = Rails.cache.fetch('admin/total_count', expires_in: 5.minutes) do
      ActsAsTenant.without_tenant { Model.count }
    end
    result count
  end
end
```

### Currency Card
```ruby
class Avo::Cards::Revenue < Avo::Cards::MetricCard
  self.id = 'revenue'
  self.label = 'Revenue'
  self.prefix = '$'
  self.format = -> { (value / 100.0).round(2) }

  def query
    total = Rails.cache.fetch('admin/revenue', expires_in: 5.minutes) do
      ActsAsTenant.without_tenant { Invoice.paid.sum(:amount_cents) }
    end
    result total
  end
end
```

### Chart Card
```ruby
class Avo::Cards::MonthlyTrend < Avo::Cards::ChartkickCard
  self.id = 'monthly_trend'
  self.label = 'Monthly Trend'
  self.chart_type = :line_chart  # :area_chart, :bar_chart, :column_chart, :pie_chart
  self.cols = 2

  def query
    data = Model.group_by_month(:created_at).count
    result data
  end
end
```

## Badge Color Map

```ruby
field :status, as: :badge, map: {
  draft: :info,       # Blue
  pending: :warning,  # Yellow
  active: :success,   # Green
  failed: :danger,    # Red
  cancelled: :secondary  # Gray
}
```

## Currency Formatting

```ruby
field :amount_cents, as: :number,
  name: 'Amount',
  format_using: -> { value ? "$#{(value / 100.0).round(2)}" : '-' }
```

## Custom Find (UUID + Subdomain)

```ruby
self.find_record_method = -> {
  if id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    query.find_by(id: id)
  else
    query.find_by(subdomain: id)
  end
}
```

## Action Responses

```ruby
succeed 'Success message'
error 'Error message'
warn 'Warning message'
redirect_to '/path'
download '/file.pdf', filename: 'report.pdf'
reload
keep_modal_open
silent
```

## Multi-Tenant Queries

```ruby
# Platform-wide (admin dashboards)
ActsAsTenant.without_tenant do
  Organization.count
end

# Scoped to current tenant (default)
Client.all  # Automatically scoped
```

## HIPAA Audit Logging

```ruby
HipaaAuditLog.create(
  user: current_user,
  action_type: 'soft_delete',
  auditable: record,
  details: { performed_via: 'avo_admin' }
)
```

## Visibility Helpers

```ruby
# View checks
view.index?
view.show?
view.edit?
view.new?

# Model checks
resource.model_class.included_modules.include?(SoftDeletable)

# Record checks (show/edit only)
record.deleted?
record.active?
```

## Authorization

```ruby
# In action
self.authorize = -> { current_user.admin? }

# In field
disabled: -> { !@resource.authorization.authorize_action(:update?, raise_exception: false) }

# In filter
self.visible = -> { Pundit.policy(current_user, resource.model_class).index? }
```
