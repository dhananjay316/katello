module Katello
  module Pulp3Support
    extend ActiveSupport::Concern

    included do
      include VCR::TestCase
    end

    PULP_TMP_DIR = "/var/lib/pulp/published/puppet_katello_test".freeze
    @repo_url = "file:///var/www/test_repos/zoo"
    @puppet_repo_url = "http://davidd.fedorapeople.org/repos/random_puppet/"
    @repo = nil

    def ensure_creatable(repo, smart_proxy)
      service = repo.backend_service(smart_proxy)
      service.class.any_instance.stubs(:backend_object_name).returns(repo.pulp_id)

      tasks = []
      if (repo = service.list(name: service.backend_object_name).first)
        tasks << service.delete(repo.pulp_href)
      end

      if (remote = service.remotes_list(name: service.backend_object_name).first)
        tasks << service.delete_remote(remote.pulp_href)
      end

      #delete distribution by name, since its not random due to vcr
      if (dist = service.lookup_distributions(name: service.backend_object_name).first)
        tasks << service.delete_distribution(dist.pulp_href)
      end
      service.delete_distributions
    end

    def wait_on_task(smart_proxy, task)
      task = task.as_json
      task = tasks_api(smart_proxy).read(task['pulp_href'] || task['task']).as_json.with_indifferent_access
      if task[:finished_at] || Actions::Pulp3::AbstractAsyncTask::FINISHED_STATES.include?(task[:state])
        return task
      else
        sleep(0.1)
        wait_on_task(smart_proxy, task)
      end
    end

    def tasks_api(smart_proxy)
      api_client = PulpcoreClient::ApiClient.new(smart_proxy.pulp3_configuration(PulpcoreClient::Configuration))
      PulpcoreClient::TasksApi.new(api_client)
    end

    def create_repo(repo, smart_proxy)
      ensure_creatable(repo, smart_proxy)
      ForemanTasks.sync_task(
        ::Actions::Pulp3::Orchestration::Repository::Create, repo, smart_proxy)
      repo.reload
    end
  end
end
