import json
import click

@click.command()
@click.option('--resfile', default='results.json', help='result file name')
@click.option('--sumfile', default='summary.log', help='summary file name')
@click.option('--failfile', default='fails.log', help='fail log file name')
@click.option('--runfile', default='run.log', help='run log file name')

def process_kirk_results(resfile, sumfile, runfile, failfile):
    summary = ''
    fail_logs = ''
    run_logs = ''

    # Load the results data from the JSON file
    with open(resfile, 'r') as results:
        results_data = json.load(results)

    for test in results_data['results']:
        summary += f'{test["test_fqn"]:30}{test["status"]}\n'

        test_log = (
                f'==== {test["test_fqn"]} ====\n'
                f'command: {test["test"]["command"]} {" ".join(test["test"]["arguments"])}\n'
                f'{test["test"]["log"]}\n'
                f'Duration: {test["test"]["duration"]:.3f}s\n\n\n'
                )

        run_logs += test_log

        if test['status'] not in ('pass', 'conf'):
            with open(f'{test["test_fqn"]}.fail.log', 'w') as failed_case:
                failed_case.write(test_log)
            fail_logs += test_log

    stats_env = (
            f'\n\nruntime:      {results_data["stats"]["runtime"]:.3f}s'
            f'\npassed          {results_data["stats"]["passed"]}'
            f'\nfailed          {results_data["stats"]["failed"]}'
            f'\nbroken          {results_data["stats"]["broken"]}'
            f'\nskipped         {results_data["stats"]["skipped"]}'
            f'\nwarnings        {results_data["stats"]["warnings"]}'
            f'\nDistribution:   {results_data["environment"]["distribution"]}-'
            f'{results_data["environment"]["distribution_version"]}'
            f'\nKernel Version: {results_data["environment"]["kernel"]}'
            f'\nSWAP:           {results_data["environment"]["swap"]}'
            f'\nRAM:            {results_data["environment"]["RAM"]}'
            )

    with open(sumfile, 'w') as summary_file:
        summary_file.write(summary)
        summary_file.write(stats_env)

    with open(failfile, 'w') as fails_file:
        fails_file.write(fail_logs)

    with open(runfile, 'w') as run_file:
        run_file.write(run_logs)

if __name__ == "__main__":
    process_kirk_results()
