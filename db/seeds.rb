# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#

5.times do
  name = Faker::Name.name
  email = "#{name.downcase.gsub(' ','.')}@test.com"
  u = User.create!(name: Faker::Name.first_name, email: email)
end

user_ids = User.ids

20.times do
  Post.create!(content: Faker::Lorem.paragraph, user_id: user_ids.sample)
end