from prometheus_client import Counter

# Prometheus metrics
users_created_total = Counter('users_created_total', 'Total number of users created')
posts_created_total = Counter('posts_created_total', 'Total number of posts created')
