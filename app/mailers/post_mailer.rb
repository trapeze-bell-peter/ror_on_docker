class PostMailer < ApplicationMailer
  def post_created(post_id)
    @post = Post.find(post_id)

    mail(to: @post.user.email, subject: 'Thank you for creating a post')
  end
end
