# relational_exporter

A gem to make it easy to export data from relational databases. RelationalExporter shines when your intended output is a "flat" CSV file, but your data is relational (each record can have multiple associated sub-records). Define your schema (once) in a familiar ActiveRecord-y way and leverage the robust model featureset. Once your schema is defined, define one or more output configurations which can be re-used to generate an export file.

## Installation

Add this line to your application's Gemfile:

    gem 'relational_exporter'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install relational_exporter

## Usage

```ruby
  # Define schemas
  my_schema = {
  	person: {
  	  table_name: :person,
  	  primary_key: :id,
  	  has_many: {
  	    addresses: nil,
  	    emails: nil
  	  },
  	  has_one: {
  	    avatar: [{ foreign_key: :ref_id }]
  	  }
  	},
  	avatar: {
  	  table_name: :avatar,
  	  belongs_to: {
  	    person: [{ foreign_key: :ref_id }]
  	  }
  	}
  }

  # Define output
  my_output_config = {
    format: :csv,
    output: {
      model: :person,
      scope: {
        where: "person.status = 'active'"
      },
      associations: {
        emails: {},
        avatar: {
          scope: {
            where: "ref_type like 'person'",
            limit: 1,
            order: "id desc"
          }
        }
      }
    }
  }

  # Define DB connection info
  my_conn = {
  	adapter: 'mysql2',
  	host: ENV['DB_HOST'],
  	username: ENV['DB_USER'],
  	password: ENV['DB_PASS'],
  	database: 'my_database'
  }

  # Run the export!
  r = RelationalExporter::Runner.new schema: my_schema, connection_config: my_conn
  r.export(my_output_config) do |record|
    # modify the record and it's models/associations
  end
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
