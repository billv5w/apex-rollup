public without sharing class RollupRepository implements RollupLogger.ToStringObject {
  public static final Integer SENTINEL_COUNT_VALUE = -1;

  private final Args args = new Args();
  private final System.AccessLevel accessLevel;
  private final PermissionLevel localPermissionLevel;

  private class Args {
    public final Map<String, Object> bindVars = new Map<String, Object>();
    public String query;
  }

  /**
   * Essentially a clone of `System.AccessLevel`, but this one:
   *  - can actually be serialized
   *  - doesn't fail an equality check against itself in a Queueable/Batchable (prior comparisons to System.AccessLevel.USER_MODE or System.AccessLevel.SYSTEM_MODE
   *  failed when the property they were referencing was stored as an instance variable post-serialization)
   */
  public enum PermissionLevel {
    SYSTEM_MODE,
    USER_MODE
  }

  public RollupRepository(PermissionLevel localPermissionLevel) {
    this.localPermissionLevel = localPermissionLevel;
    this.accessLevel = localPermissionLevel == PermissionLevel.USER_MODE ? System.AccessLevel.USER_MODE : System.AccessLevel.SYSTEM_MODE;
  }

  public RollupRepository setQuery(String query) {
    this.args.query = query;
    return this;
  }

  public RollupRepository setArg(Object value) {
    this.args.bindVars.put(RollupQueryBuilder.BIND_VAR, value);
    return this;
  }

  public RollupRepository setArg(String key, Object value) {
    this.args.bindVars.put(key, value);
    return this;
  }

  public Database.QueryLocator getLocator() {
    this.createQueryLog('Getting query locator');
    return Database.getQueryLocatorWithBinds(this.args.query, this.args.bindVars, this.accessLevel);
  }

  public List<SObject> get() {
    this.createQueryLog('Querying...');
    return Database.queryWithBinds(this.args.query, this.args.bindVars, this.accessLevel);
  }

  public Integer getCount() {
    if (this.args.query.contains(RollupQueryBuilder.ALL_ROWS)) {
      this.args.query = this.args.query.replace(RollupQueryBuilder.ALL_ROWS, '');
    }
    this.args.query = this.args.query.replaceFirst('SELECT.+\n', 'SELECT Count()\n');

    Integer countAmount;
    try {
      countAmount = Database.countQueryWithBinds(this.args.query, this.args.bindVars, this.accessLevel);
    } catch (Exception ex) {
      RollupLogger.Instance.log('an error occurred while trying to get count query', ex, LoggingLevel.WARN);
      // not all count queries are valid, particularly those with polymorphic fields referencing parent fields
      // return a sentinel value instead, to be checked for downstream
      countAmount = SENTINEL_COUNT_VALUE;
    }
    this.createQueryLog('Returned amount: ' + countAmount);
    return countAmount;
  }

  public override String toString() {
    return this.args.query + '\nBind keys: ' + this.args.bindVars.keySet() + '\nAccess level: ' + this.localPermissionLevel;
  }

  private void createQueryLog(String message) {
    RollupLogger.Instance.Log(message, this, LoggingLevel.DEBUG);
  }
}
