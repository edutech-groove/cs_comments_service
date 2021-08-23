post "#{APIPREFIX}/users" do
  user = User.new(external_id: params["id"])
  user.username = params["username"]
  user.save
  if user.errors.any?
    error 400, user.errors.full_messages.to_json
  else
    user.to_hash.to_json
  end
end

get "#{APIPREFIX}/users/:user_id" do |user_id|
  begin
    # Get any group_ids that may have been specified (will be an empty list if none specified).
    group_ids = get_group_ids_from_params(params)
    user.to_hash(complete: bool_complete, course_id: params["course_id"], group_ids: group_ids).to_json
  rescue Mongoid::Errors::DocumentNotFound
    error 404
  end
end

get "#{APIPREFIX}/users/:user_id/active_threads" do |user_id|
  return {}.to_json if not params["course_id"]

  page = (params["page"] || DEFAULT_PAGE).to_i
  per_page = (params["per_page"] || DEFAULT_PER_PAGE).to_i
  per_page = DEFAULT_PER_PAGE if per_page <= 0

  active_contents = Content.where(author_id: user_id, anonymous: false, anonymous_to_peers: false, course_id: params["course_id"])
                           .order_by(updated_at: :desc)

  # Get threads ordered by most recent activity, taking advantage of the fact
  # that active_contents is already sorted that way
  active_thread_ids = active_contents.inject([]) do |thread_ids, content|
    thread_id = content._type == "Comment" ? content.comment_thread_id : content.id
    thread_ids << thread_id if not thread_ids.include?(thread_id)
    thread_ids
  end

  threads = CommentThread.in({"_id" => active_thread_ids})

  group_ids = get_group_ids_from_params(params)
  if not group_ids.empty?
    threads = get_group_id_criteria(threads, group_ids)
  end
  
  handle_threads_query(
    threads,
    params["user_id"],
    params["course_id"],
    get_group_ids_from_params(params),
    value_to_boolean(params["flagged"]),
    value_to_boolean(params["unread"]),
    value_to_boolean(params["unanswered"]),
    params["sort_key"],
    params["page"],
    params["per_page"]
  ).to_json

end

put "#{APIPREFIX}/users/:user_id" do |user_id|
  user = User.find_or_create_by(external_id: user_id)
  user.update_attributes(params.slice(*%w[username default_sort_key]))
  if user.errors.any?
    error 400, user.errors.full_messages.to_json
  else
    user.to_hash.to_json
  end
end

post "#{APIPREFIX}/users/:user_id/read" do |user_id|
  user.mark_as_read(source)
  user.reload.to_hash.to_json
end

post "#{APIPREFIX}/users/:user_id/retire" do |user_id|
  if not params["retired_username"]
    error 500, {message: "Missing retired_username param."}.to_json
  end
  begin
    user = User.find_by(external_id: user_id)
  rescue Mongoid::Errors::DocumentNotFound
    error 404, {message: "User not found."}.to_json
  end
  user.update_attribute(:email, "")
  user.update_attribute(:notification_ids, [])
  user.update_attribute(:read_states, [])
  user.unsubscribe_all
  user.retire_all_content(params["retired_username"])
  user.update_attribute(:username, params["retired_username"])
  user.save
end
