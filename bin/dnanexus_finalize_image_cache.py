#!/usr/bin/env python3
"""Archive superseded same-name cache files after a successful importer build."""
import argparse
from collections import defaultdict

import dxpy


def finalize_cache(job_id, project_id, archive_folder):
    job = dxpy.DXJob(job_id).describe()
    if job.get('state') != 'done' or job.get('project') != project_id:
        raise ValueError('Importer must have succeeded in the destination project')
    applet_id, _ = dxpy.get_dxlink_ids(job['output']['output_applet'])
    applet = dxpy.DXApplet(applet_id, project=project_id).describe()
    bundles = list(applet.get('runSpec', {}).get('bundledDepends', []))
    for region in applet.get('regionalOptions', {}).values():
        bundles.extend(region.get('bundledDepends', []))

    selected = defaultdict(set)
    seen = set()
    for bundle in bundles:
        file_id, linked_project = dxpy.get_dxlink_ids(bundle['id'])
        if file_id in seen or linked_project not in (None, project_id):
            continue
        seen.add(file_id)
        metadata = dxpy.DXFile(file_id, project=project_id).describe()
        folder = metadata.get('folder', '')
        if folder.startswith('/.cached_docker_images/'):
            if metadata.get('state') != 'closed':
                raise ValueError(f'Cached image is not closed: {file_id}')
            selected[folder, metadata['name']].add(file_id)
    if not selected:
        raise ValueError('Importer applet has no project-cached Docker image bundles')

    # Plan all moves before making changes. Only the importer's image/tag names
    # are affected; old applets can still reference archived files by ID.
    moves = []
    for (folder, name), keep_ids in selected.items():
        matches = dxpy.find_data_objects(
            project=project_id, classname='file', state='closed',
            folder=folder, recurse=False, name=name)
        stale = sorted(item['id'] for item in matches if item['id'] not in keep_ids)
        if stale:
            target = archive_folder.rstrip('/') + folder.removeprefix('/.cached_docker_images')
            moves.append((target, stale))
    project = dxpy.DXProject(project_id)
    for target, stale in moves:
        project.new_folder(target, parents=True)
        project.move(destination=target, objects=stale)
        print(f'Archived {len(stale)} superseded image cache file(s) in {project_id}:{target}')
    print(f'Image cache ready: {len(selected)} image/tag reference(s)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--job', required=True)
    parser.add_argument('--project', required=True)
    parser.add_argument('--archive-folder', required=True)
    args = parser.parse_args()
    finalize_cache(args.job, args.project, args.archive_folder)


if __name__ == '__main__':
    main()
